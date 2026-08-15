package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ComponentMediaServiceTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void selectsOnlyThePrimaryControlPlaneArchitectureAndCapturesChecksums() throws Exception {
        Files.createDirectories(temporaryDirectory.resolve("tools"));
        Files.writeString(temporaryDirectory.resolve("tools/helm-amd"), "amd64", StandardCharsets.UTF_8);
        Files.writeString(temporaryDirectory.resolve("tools/helm-arm"), "arm64", StandardCharsets.UTF_8);
        ComponentMediaService media = new ComponentMediaService(temporaryDirectory);

        InstallStep.Resource resource = media.helmResource(snapshot("arm64"));
        InstallStep step = new InstallStep("29-install-helm", "Helm", "component", "primary_control_plane",
                temporaryDirectory.resolve("script.sh"), null, "serial", 1, true, List.of(resource),
                List.of(), List.of(), "", null);
        InstallPlan verified = media.verifyAndChecksum(new InstallPlan(List.of(step)));
        InstallStep.Resource checked = verified.require("29-install-helm").resources().get(0);

        assertThat(checked.localPath().toString().replace('\\', '/')).endsWith("tools/helm-arm");
        assertThat(checked.remotePath()).isEqualTo("/tmp/kubefoundry/jobs/{job_id}/resources/shared/helm");
        assertThat(checked.checksum()).hasSize(64);
        assertThat(media.checksums(verified)).containsKey("tools/helm-arm");
    }

    @Test
    void rejectsMissingMediaBeforeJobSubmission() throws Exception {
        ComponentMediaService media = new ComponentMediaService(temporaryDirectory);
        InstallStep.Resource missing = InstallStep.Resource.local(temporaryDirectory.resolve("missing"), "file",
                "/tmp/kubefoundry/jobs/{job_id}/resources/shared/missing");
        InstallStep step = new InstallStep("resource", "Resource", "component", "primary_control_plane",
                temporaryDirectory.resolve("script.sh"), null, "serial", 1, true, List.of(missing),
                List.of(), List.of(), "", null);

        assertThatThrownBy(() -> media.verifyAndChecksum(new InstallPlan(List.of(step))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("missing");
    }

    @Test
    void assignsEveryComponentStepAnIndependentPermanentRemoteResourceDirectory() throws Exception {
        Path minio = temporaryDirectory.resolve(
                "kube-media/03.setup_file/v1.29.3/minio");
        Files.createDirectories(minio);
        Files.writeString(minio.resolve("tenant.yaml"), "kind: Tenant\n", StandardCharsets.UTF_8);
        ComponentMediaService media = new ComponentMediaService(temporaryDirectory);

        InstallStep.Resource resource = media.componentResource(
                snapshot("amd64"), "storage_observability", "49-install-minio");

        assertThat(resource.remotePath()).isEqualTo(
                "/tmp/kubefoundry/jobs/{job_id}/resources/storage_observability/49-install-minio");
    }

    private static InstallationSnapshotPayload snapshot(String architecture) {
        Cluster cluster = new Cluster("component-media");
        ReflectionTestUtils.setField(cluster, "id", 1L);
        cluster.updateInstallationConfiguration("/data/kubernetes", "REGISTRY");
        cluster.updateKubemateEnabled(true);
        Node node = new Node(cluster);
        ReflectionTestUtils.setField(node, "id", 2L);
        node.update("cp-1", "10.0.0.1", "", "control_plane", "root", 22);
        node.completeNodeTest("kylin", "V10", architecture);
        return InstallationSnapshotPayload.capture(cluster, List.of(node), List.of(), Map.of());
    }
}
