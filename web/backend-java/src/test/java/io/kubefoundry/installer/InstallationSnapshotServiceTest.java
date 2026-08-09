package io.kubefoundry.installer;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponentRepository;
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

    private static InstallationSnapshot snapshot(
            ObjectMapper mapper, Cluster cluster, String jobType, Map<String, String> checksums) throws Exception {
        Job job = new Job(cluster, jobType);
        job.markSuccess();
        InstallationSnapshotPayload payload = new InstallationSnapshotPayload(
                1L, "cluster", "1", "/data/k8s", "REGISTRY", List.of(), 1L,
                List.of(), "v0.3.0", checksums);
        return new InstallationSnapshot(job, cluster, mapper.writeValueAsString(payload));
    }
}
