package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:cluster-settings;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=validate"
})
class ClusterSettingsServiceTest {

    @Autowired
    ClusterRepository clusters;

    @Autowired
    NodeRepository nodes;

    @Autowired
    ClusterSettingsService settings;

    @Autowired
    JdbcTemplate jdbc;

    @AfterEach
    void cleanUp() {
        clusters.deleteAll();
    }

    @Test
    void storesPathsEnvAndAdvancedInClusterSettingsWithPythonCompatibleDefaults() {
        Cluster cluster = clusters.save(new Cluster("settings-test"));
        cluster.update(null, null, "1.30.2", "10.244.0.0/16", "10.96.0.0/12",
                "registry", "10.0.0.9", 5000, null);
        Node node = nodes.save(node(cluster, "cp-a", "10.0.0.1", "control_plane", "arm64"));

        Map<String, Object> defaults = settings.getGlobalSettings();
        assertThat(defaults).containsKeys("paths", "env", "advanced");
        assertThat(group(defaults, "paths")).containsEntry("k8s_home", "/data/k8s_install")
                .containsEntry("install_media", "/root/kube-media");
        assertThat(group(defaults, "env")).containsEntry("containerd_root",
                "/data/k8s_install/containerd-data");

        settings.updateClusterSettings(cluster.getId(), Map.of(
                "paths", Map.of(
                        "k8s_home", "/opt/k8s",
                        "install_media", "/mnt/media",
                        "container_runtime", "${install_media}/runtime/${arch}"),
                "env", Map.of(
                        "kubelet_root", "/var/lib/kubelet",
                        "containerd_root", "/var/lib/containerd",
                        "etcd_data_dir", "/var/lib/etcd"),
                "advanced", Map.of("enable_ipv6_dual_stack", true)));

        Map<String, Object> merged = settings.getClusterSettings(cluster.getId());
        assertThat(group(merged, "paths")).containsEntry("k8s_home", "/opt/k8s")
                .containsEntry("container_runtime", "${install_media}/runtime/${arch}");
        assertThat(group(merged, "env")).containsEntry("etcd_data_dir", "/var/lib/etcd");
        assertThat(group(merged, "advanced")).containsEntry("enable_ipv6_dual_stack", true);
        assertThat(jdbc.queryForObject(
                "select count(*) from cluster_settings where cluster_id=?",
                Integer.class, cluster.getId())).isEqualTo(3);

        RuntimeSettings runtime = settings.runtimeSettings(cluster, node);
        assertThat(runtime.k8sHome()).isEqualTo("/opt/k8s");
        assertThat(runtime.installMedia()).isEqualTo("/mnt/media");
        assertThat(runtime.path("container_runtime")).isEqualTo("/mnt/media/runtime/arm64");

        String rendered = new RuntimeEnvRenderer().render(cluster, List.of(node), node, runtime);
        assertThat(rendered).contains(
                "export KF_K8S_HOME='/opt/k8s'",
                "export KF_INSTALL_MEDIA='/mnt/media'",
                "export KF_KUBELET_ROOT='/var/lib/kubelet'",
                "export KF_CONTAINERD_ROOT='/var/lib/containerd'",
                "export KF_ETCD_DATA_DIR='/var/lib/etcd'",
                "export KF_DUAL_STACK='Y'");
        assertThat(rendered).doesNotContainIgnoringCase("password")
                .doesNotContainIgnoringCase("private_key")
                .doesNotContainIgnoringCase("ciphertext");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> group(Map<String, Object> settings, String key) {
        return (Map<String, Object>) settings.get(key);
    }

    private static Node node(
            Cluster cluster, String hostname, String ip, String role, String architecture) {
        Node node = new Node(cluster);
        node.update(hostname, ip, "", role, "root", 22);
        node.completeNodeTest("kylin", "V10", architecture);
        return node;
    }
}
