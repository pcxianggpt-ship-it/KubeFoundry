package io.kubefoundry.installer;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.ClusterComponent;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class InstallationSnapshotServiceTest {

    @Test
    void resetPayloadPrefersNewestSuccessfulComponentMediaOverBaseInstallMedia() throws Exception {
        Cluster cluster = new Cluster("cluster");
        ReflectionTestUtils.setField(cluster, "id", 1L);
        InstallationSnapshotRepository snapshots = mock(InstallationSnapshotRepository.class);
        ObjectMapper mapper = new ObjectMapper();
        InstallationSnapshot base = snapshot(mapper, cluster, "install", Map.of(
                "kube-media/03.setup_file/v1/helmapp/nfs/nfs-subdir-external-provisioner",
                "a".repeat(64),
                "kube-media/base.tar", "b".repeat(64)));
        InstallationSnapshot olderComponent = snapshot(mapper, cluster,
                ComponentInstallationStateService.JOB_TYPE, Map.of(
                        "kube-media/03.setup_file/v1/helmapp/nfs/nfs-subdir-external-provisioner",
                        "c".repeat(64)));
        InstallationSnapshot newestComponent = snapshot(mapper, cluster,
                ComponentInstallationStateService.JOB_TYPE, Map.of(
                        "kube-media/03.setup_file/v1/helmapp/nfs/nfs-subdir-external-provisioner",
                        "d".repeat(64)));
        when(snapshots.findTopByCluster_IdAndJob_TypeOrderByIdDesc(1L, "install"))
                .thenReturn(Optional.of(base));
        when(snapshots.findByCluster_IdAndJob_TypeAndJob_StatusOrderByIdDesc(
                1L, ComponentInstallationStateService.JOB_TYPE, "success"))
                .thenReturn(List.of(newestComponent, olderComponent));
        InstallationSnapshotService service = new InstallationSnapshotService(
                snapshots, mock(JobRepository.class), mock(ClusterComponentRepository.class), mapper);

        InstallationSnapshotPayload payload = service.latestInstallPayload(1L);

        assertThat(payload.mediaChecksums()).containsEntry(
                "kube-media/03.setup_file/v1/helmapp/nfs/nfs-subdir-external-provisioner",
                "d".repeat(64));
        assertThat(payload.mediaChecksums()).containsEntry("kube-media/base.tar", "b".repeat(64));
    }

    @Test
    void freezesValidatedMinioConfigurationIntoSnapshotRuntimeSettings() {
        Cluster cluster = new Cluster("minio-snapshot");
        ReflectionTestUtils.setField(cluster, "id", 7L);
        cluster.updateInstallationConfiguration("/data/k8s", "REGISTRY");
        Node worker = new Node(cluster);
        ReflectionTestUtils.setField(worker, "id", 11L);
        worker.update("worker-a", "10.0.0.11", "", "worker", "root", 22);
        worker.replaceRoles(java.util.Set.of("worker"));
        ClusterComponentRepository components = mock(ClusterComponentRepository.class);
        when(components.findByClusterIdOrderByComponentKey(7L)).thenReturn(List.of(new ClusterComponent(
                cluster, "storage_observability", true,
                "{\"minio_pvc_size\":\"20Gi\",\"minio_cpu_request\":\"500m\","
                        + "\"minio_cpu_limit\":\"2\",\"minio_memory_request\":\"1Gi\","
                        + "\"minio_memory_limit\":\"4Gi\"}")));
        ClusterSettingsService settings = mock(ClusterSettingsService.class);
        when(settings.runtimeSettings(cluster, worker)).thenReturn(
                new RuntimeSettings(Map.of("k8s_home", "/data/k8s"), Map.of(), Map.of()));
        InstallationSnapshotService service = new InstallationSnapshotService(
                mock(InstallationSnapshotRepository.class), mock(JobRepository.class),
                components, new ObjectMapper(), settings);

        InstallationSnapshotPayload payload = service.previewPayload(cluster, List.of(worker));

        assertThat(payload.componentGroups().get(0).config())
                .containsEntry("minio_pvc_size", "20Gi");
        assertThat(payload.runtimeSettings().get(11L).env())
                .containsEntry("minio_pvc_size", "20Gi")
                .containsEntry("minio_cpu_request", "500m")
                .doesNotContainKeys("password", "secret", "credential");
    }

    private static InstallationSnapshot snapshot(
            ObjectMapper mapper, Cluster cluster, String jobType, Map<String, String> checksums) throws Exception {
        Job job = new Job(cluster, jobType);
        ReflectionTestUtils.setField(job, "id", Math.abs((long) checksums.hashCode()) + 1L);
        job.markSuccess();
        InstallationSnapshotPayload payload = new InstallationSnapshotPayload(
                1L, "cluster", "1", "/data/k8s", "REGISTRY", List.of(), 1L,
                List.of(), "v0.3.0", checksums);
        return new InstallationSnapshot(job, cluster, mapper.writeValueAsString(payload));
    }
}
