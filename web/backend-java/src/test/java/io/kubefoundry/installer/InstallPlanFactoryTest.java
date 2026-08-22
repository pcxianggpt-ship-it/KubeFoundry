package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.nio.file.Path;
import java.nio.file.Files;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class InstallPlanFactoryTest {

    @TempDir
    Path temporaryDirectory;

    private InstallPlanFactory factory;

    @BeforeEach
    void createFactory() {
        factory = new InstallPlanFactory(temporaryDirectory);
    }

    @Test
    void mapsAllBaseInstallationStepsInOrder() {
        InstallPlan plan = factory.create();

        assertThat(plan.steps()).extracting(InstallStep::key).containsExactly(
                "10-setup-yum-source",
                "11b-setup-hostname",
                "12-setup-k8s-repo",
                "13-install-k8s-deps",
                "14-replace-kubeadm",
                "15-environment-config",
                "16-install-containerd",
                "17-install-registry",
                "18-init-k8s-cluster",
                "19-modify-cert-expiry",
                "20-add-control-nodes",
                "21-add-worker-nodes",
                "22-install-cni-flannel",
                "23-configure-coredns-affinity",
                "web-verify-cluster-health");
        assertThat(plan.steps()).hasSize(15);
        assertThat(plan.require("web-verify-cluster-health").builtin())
                .isEqualTo("cluster_health");

        InstallStep dependencies = plan.require("13-install-k8s-deps");
        InstallStep containerd = plan.require("16-install-containerd");
        assertThat(dependencies.mode()).isEqualTo("parallel");
        assertThat(dependencies.maxWorkers()).isEqualTo(5);
        assertThat(dependencies.failFast()).isFalse();
        assertThat(containerd.mode()).isEqualTo("parallel");
        assertThat(containerd.maxWorkers()).isEqualTo(5);

        InstallStep initialize = plan.require("18-init-k8s-cluster");
        InstallStep joinControls = plan.require("20-add-control-nodes");
        assertThat(initialize.mode()).isEqualTo("serial");
        assertThat(initialize.maxWorkers()).isEqualTo(1);
        assertThat(initialize.outputs()).extracting(InstallStep.Output::key)
                .containsExactly("control_join", "worker_join");
        assertThat(initialize.verifyScript()).isEqualTo(temporaryDirectory.resolve(
                "scripts/verify/phase2_k8s_base/verify-18-init-k8s-cluster.sh").toAbsolutePath());
        assertThat(initialize.recoveryScript()).isEqualTo(temporaryDirectory.resolve(
                "scripts/recovery/phase2_k8s_base/recover-18-init-k8s-cluster-outputs.sh")
                .toAbsolutePath());
        assertThat(joinControls.mode()).isEqualTo("serial");
        assertThat(joinControls.maxWorkers()).isEqualTo(1);
        assertThat(joinControls.resources()).extracting(InstallStep.Resource::artifactKey)
                .containsExactly("control_join");
    }

    @Test
    void preservesScriptsResourcesArgumentsAndVerificationCommands() {
        InstallPlan plan = factory.create();

        assertThat(plan.require("10-setup-yum-source").script())
                .isEqualTo(temporaryDirectory.resolve(
                        "scripts/steps/phase2_k8s_base/10-setup-yum-source.sh"));
        assertThat(plan.require("10-setup-yum-source").resources())
                .containsExactly(new InstallStep.Resource(
                        "repo_source", null, "file", "/tmp/k8s/k8s-repo-source.tar.gz"));
        assertThat(plan.require("10-setup-yum-source").arguments())
                .containsExactly(new InstallStep.Argument("/tmp/k8s/k8s-repo-source.tar.gz", null));
        assertThat(plan.require("11b-setup-hostname").builtin()).isEqualTo("setup_hostname");
        assertThat(plan.steps().subList(0, 14))
                .allSatisfy(step -> {
                    assertThat(step.type()).isEqualTo(InstallStep.StepType.INSTALL);
                    assertThat(step.verifyScript()).isNotNull();
                    assertThat(step.verifyCommand()).isBlank();
                });
        assertThat(plan.require("web-verify-cluster-health").type())
                .isEqualTo(InstallStep.StepType.VALIDATION);
        assertThat(plan.require("web-verify-cluster-health").verifyScript()).isNull();
    }

    @Test
    void resolvesTargetsByRepositoryIdOrderWithRegistryIpAndStableDeduplication() {
        Cluster cluster = new Cluster("target-test");
        cluster.update(null, null, null, null, null, null, "10.0.0.3", null, null);
        Node cpB = node(cluster, 1L, "cp-b", "10.0.0.2", "control_plane");
        Node worker = node(cluster, 2L, "worker-a", "10.0.0.3", "worker");
        Node duplicateWorker = node(cluster, 3L, "worker-copy", "10.0.0.3", "worker");
        Node cpA = node(cluster, 4L, "cp-a", "10.0.0.1", "control_plane");
        Node registry = node(cluster, 5L, "registry", "10.0.0.4", "registry");
        List<Node> nodes = List.of(cpB, worker, duplicateWorker, cpA, registry);
        InstallPlan plan = factory.create();

        assertThat(factory.resolveTargets(plan.require("18-init-k8s-cluster"), cluster, nodes))
                .extracting(Node::getHostname).containsExactly("cp-b");
        assertThat(factory.resolveTargets(plan.require("20-add-control-nodes"), cluster, nodes))
                .extracting(Node::getHostname).containsExactly("cp-a");
        assertThat(factory.resolveTargets(plan.require("13-install-k8s-deps"), cluster, nodes))
                .extracting(Node::getHostname).containsExactly("cp-b", "worker-a", "cp-a");
        assertThat(factory.resolveTargets(plan.require("16-install-containerd"), cluster, nodes))
                .extracting(Node::getHostname)
                .containsExactly("cp-b", "worker-a", "cp-a", "registry");
        assertThat(factory.resolveTargets(plan.require("17-install-registry"), cluster, nodes))
                .extracting(Node::getHostname).containsExactly("registry");
    }

    @Test
    void usesTheFirstControlPlaneByNodeIdForPrimaryAndOtherControlTargets() {
        Cluster cluster = new Cluster("multi-control");
        Node laterByName = node(cluster, 20L, "a-control", "10.0.0.20", "control_plane");
        Node primaryById = node(cluster, 10L, "z-control", "10.0.0.10", "control_plane");
        Node worker = node(cluster, 30L, "worker-a", "10.0.0.30", "worker");
        InstallPlan plan = factory.create();

        assertThat(factory.resolveTargets(plan.require("18-init-k8s-cluster"), cluster,
                List.of(laterByName, worker, primaryById)))
                .extracting(Node::getHostname).containsExactly("z-control");
        assertThat(factory.resolveTargets(plan.require("20-add-control-nodes"), cluster,
                List.of(laterByName, worker, primaryById)))
                .extracting(Node::getHostname).containsExactly("a-control");
    }

    @Test
    void rejectsUnknownSelectionAndMissingArtifactProducer() {
        assertThatThrownBy(() -> factory.select(List.of("missing")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("missing");
        assertThatThrownBy(() -> factory.select(List.of("20-add-control-nodes")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("control_join");
    }

    @Test
    void discoversRepositoryRootFromNestedBackendWorkingDirectory() throws Exception {
        Path root = temporaryDirectory.resolve("repository");
        Files.createDirectories(root.resolve("scripts/steps"));
        Path backend = Files.createDirectories(root.resolve("web/backend-java"));

        assertThat(InstallPlanFactory.discoverProjectRoot(backend)).isEqualTo(root);
    }

    private static Node node(
            Cluster cluster, long id, String hostname, String ip, String role) {
        Node node = new Node(cluster);
        ReflectionTestUtils.setField(node, "id", id);
        node.update(hostname, ip, "", role, "root", 22);
        return node;
    }
}
