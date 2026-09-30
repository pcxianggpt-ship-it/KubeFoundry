package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;

class RuntimeEnvRendererTest {

    @Test
    void rendersPythonCompatibleEnvironmentWithStrictPosixQuoting() {
        Cluster cluster = new Cluster("prod'cluster");
        cluster.update(null, null, "1.29.3", "10.244.0.0/16", "10.96.0.0/12",
                "registry.internal", "10.0.0.9", 5000, null);
        Node primary = node(cluster, "cp-a", "10.0.0.1", "control_plane", "amd64");
        Node worker = node(cluster, "worker-a", "10.0.0.2", "worker", "arm64");

        String rendered = new RuntimeEnvRenderer().render(cluster, List.of(worker, primary), worker);

        assertThat(rendered).startsWith("#!/bin/bash\n");
        assertThat(rendered).doesNotContain("\r");
        assertThat(rendered).contains("export KF_CLUSTER_NAME='prod'\"'\"'cluster'");
        assertThat(rendered).contains("export KF_NODE_HOSTNAME='worker-a'");
        assertThat(rendered).contains("export KF_ARCH='arm64'");
        assertThat(rendered).contains("export KF_PRIMARY_CONTROL_HOSTNAME='cp-a'");
        assertThat(rendered).contains("export KUBECONFIG=\"${KF_KUBECONFIG}\"");
        assertThat(rendered).contains("export K8S_VERSION=\"${KF_K8S_VERSION}\"");
        assertThat(rendered).contains("log_info()", "log_success()", "log_error()");
        assertThat(rendered).doesNotContainIgnoringCase("password");
        assertThat(rendered).doesNotContainIgnoringCase("private_key");
    }

    @Test
    void usesTheFirstControlPlaneByNodeIdForPrimaryEnvironmentVariables() {
        Cluster cluster = new Cluster("multi-control");
        Node laterByName = node(cluster, "a-control", "10.0.0.20", "control_plane", "amd64");
        Node primaryById = node(cluster, "z-control", "10.0.0.10", "control_plane", "amd64");
        Node worker = node(cluster, "worker-a", "10.0.0.30", "worker", "amd64");
        ReflectionTestUtils.setField(laterByName, "id", 20L);
        ReflectionTestUtils.setField(primaryById, "id", 10L);
        ReflectionTestUtils.setField(worker, "id", 30L);

        String rendered = new RuntimeEnvRenderer().render(
                cluster, List.of(laterByName, worker, primaryById), worker);

        assertThat(rendered).contains(
                "export KF_PRIMARY_CONTROL_HOSTNAME='z-control'",
                "export KF_PRIMARY_CONTROL_IP='10.0.0.10'");
    }

    @Test
    void normalizesDuplicateIpsBeforeSelectingPrimaryEnvironmentVariables() {
        Cluster cluster = new Cluster("duplicate-ip-runtime");
        Node canonicalWorker = node(cluster, "worker-a", "10.0.0.10", "worker", "amd64");
        Node duplicateControl = node(cluster, "duplicate-control", "10.0.0.10", "control_plane", "amd64");
        Node canonicalControl = node(cluster, "cp-a", "10.0.0.30", "control_plane", "amd64");
        ReflectionTestUtils.setField(canonicalWorker, "id", 10L);
        ReflectionTestUtils.setField(duplicateControl, "id", 20L);
        ReflectionTestUtils.setField(canonicalControl, "id", 30L);

        String rendered = new RuntimeEnvRenderer().render(
                cluster, List.of(duplicateControl, canonicalControl, canonicalWorker), canonicalWorker);

        assertThat(rendered).contains(
                "export KF_PRIMARY_CONTROL_HOSTNAME='cp-a'",
                "export KF_PRIMARY_CONTROL_IP='10.0.0.30'")
                .doesNotContain("export KF_PRIMARY_CONTROL_HOSTNAME='duplicate-control'");
    }

    @Test
    void rendersOnlyWhitelistedMinioResourceValuesWithoutCredentials() {
        Cluster cluster = new Cluster("minio-runtime");
        Node node = node(cluster, "cp-a", "10.0.0.1", "control_plane", "amd64");
        RuntimeSettings settings = new RuntimeSettings(Map.of(), Map.of(
                "minio_pvc_size", "20Gi",
                "minio_cpu_request", "500m",
                "minio_cpu_limit", "2",
                "minio_memory_request", "1Gi",
                "minio_memory_limit", "4Gi"), Map.of());

        String rendered = new RuntimeEnvRenderer().render(cluster, List.of(node), node, settings);

        assertThat(rendered).contains(
                "export KF_MINIO_PVC_SIZE='20Gi'",
                "export KF_MINIO_CPU_REQUEST='500m'",
                "export KF_MINIO_MEMORY_LIMIT='4Gi'")
                .doesNotContainIgnoringCase("credential")
                .doesNotContainIgnoringCase("secret");
    }

    static Node node(
            Cluster cluster, String hostname, String ip, String role, String architecture) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", role, "root", 22);
        node.completeNodeTest("kylin", "V10", architecture);
        return node;
    }
}
