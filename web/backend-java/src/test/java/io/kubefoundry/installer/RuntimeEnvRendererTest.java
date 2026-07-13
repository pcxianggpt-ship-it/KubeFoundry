package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import java.util.List;
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

    static Node node(
            Cluster cluster, String hostname, String ip, String role, String architecture) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", role, "root", 22);
        node.completeNodeTest("kylin", "V10", architecture);
        return node;
    }
}
