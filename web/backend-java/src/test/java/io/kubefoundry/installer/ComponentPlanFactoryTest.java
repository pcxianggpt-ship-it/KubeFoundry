package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;

class ComponentPlanFactoryTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void generatesOnlyEnabledGroupsAfterTheSharedPrerequisites() {
        ComponentPlanFactory factory = new ComponentPlanFactory(temporaryDirectory);

        InstallPlan plan = factory.create(snapshot(true, List.of(
                group("traefik", true), group("prometheus", false))));

        assertThat(plan.steps()).extracting(InstallStep::key).containsExactly(
                "29-install-helm", "30-create-namespace", "36-install-traefik");
        assertThat(plan.require("36-install-traefik").componentGroupKey()).isEqualTo("traefik");
        assertThat(plan.require("29-install-helm").componentGroupKey()).isNull();
    }

    @Test
    void keepsTheStorageObservabilitySuiteAtomicAndOrdered() {
        ComponentPlanFactory factory = new ComponentPlanFactory(temporaryDirectory);

        InstallPlan plan = factory.create(snapshot(true, List.of(group("storage_observability", true))));

        assertThat(plan.steps()).extracting(InstallStep::key).containsExactly(
                "29-install-helm", "30-create-namespace", "46-prepare-storage-workers", "47-install-openebs",
                "49-install-minio", "35-install-loki", "48-install-alloy");
        assertThat(plan.steps().subList(2, 6)).extracting(InstallStep::componentGroupKey)
                .containsOnly("storage_observability");
    }

    @Test
    void usesTheActualMinioMediaDirectoryAndSkipsMetricsServerMediaValidation() {
        ComponentPlanFactory factory = new ComponentPlanFactory(temporaryDirectory);

        InstallPlan storagePlan = factory.create(snapshot(true, List.of(group("storage_observability", true))));
        InstallPlan prometheusPlan = factory.create(snapshot(true, List.of(group("prometheus", true))));

        assertThat(storagePlan.require("49-install-minio").resources()).singleElement().satisfies(resource ->
                assertThat(resource.localPath().toString().replace('\\', '/'))
                        .endsWith("kube-media/03.setup_file/vunknown/minio"));
        assertThat(prometheusPlan.require("40-install-metrics-server").resources()).isEmpty();
    }

    @Test
    void disablesAllComponentStepsWhenTheGlobalSwitchIsOffAndAppendsToBasePlan() {
        ComponentPlanFactory componentPlans = new ComponentPlanFactory(temporaryDirectory);
        InstallationSnapshotPayload disabled = snapshot(false, List.of(group("traefik", true)));

        assertThat(componentPlans.create(disabled).steps()).isEmpty();
        InstallPlan combined = new InstallPlanAssembler(
                new BaseInstallPlanFactory(temporaryDirectory), componentPlans)
                .forNewCluster(snapshot(true, List.of(group("traefik", true))));
        assertThat(combined.steps()).hasSize(17);
        assertThat(combined.steps().get(13).key()).isEqualTo("web-verify-cluster-health");
        assertThat(combined.steps().get(14).key()).isEqualTo("29-install-helm");
    }

    @Test
    void sendsKubemateManifestToTheJobResourceDirectory() {
        ComponentPlanFactory factory = new ComponentPlanFactory(temporaryDirectory);

        InstallStep step = factory.create(snapshot(true, List.of(group("kubemate", true))))
                .require("31-install-kubemate-ui");

        assertThat(step.resources()).hasSize(1);
        assertThat(step.resources().get(0).remotePath())
                .endsWith("/resources/kubemate/31-install-kubemate-ui");
    }

    private static InstallationSnapshotPayload snapshot(
            boolean enabled, List<InstallationSnapshotPayload.ComponentGroup> groups) {
        Cluster cluster = new Cluster("component-plan");
        ReflectionTestUtils.setField(cluster, "id", 1L);
        cluster.updateInstallationConfiguration("/data/kubernetes", "REGISTRY");
        cluster.updateKubemateEnabled(enabled);
        Node node = new Node(cluster);
        ReflectionTestUtils.setField(node, "id", 2L);
        node.update("cp-1", "10.0.0.1", "", "control_plane", "root", 22);
        return InstallationSnapshotPayload.capture(cluster, List.of(node), groups, Map.of());
    }

    private static InstallationSnapshotPayload.ComponentGroup group(String key, boolean enabled) {
        return new InstallationSnapshotPayload.ComponentGroup(key, enabled, Map.of());
    }
}
