package io.kubefoundry.installer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobRepository;
import java.util.List;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.stereotype.Service;

@Service
public class InstallationSnapshotService {

    private final InstallationSnapshotRepository snapshots;
    private final JobRepository jobs;
    private final ObjectMapper mapper;

    public InstallationSnapshotService(
            InstallationSnapshotRepository snapshots, JobRepository jobs, ObjectMapper mapper) {
        this.snapshots = snapshots;
        this.jobs = jobs;
        this.mapper = mapper;
    }

    @Transactional
    public void capture(long jobId, Cluster cluster, List<Node> nodes) {
        Job job = jobs.findById(jobId)
                .orElseThrow(() -> new IllegalArgumentException("安装任务不存在: " + jobId));
        if (!"install".equals(job.getType())) {
            throw new IllegalArgumentException("只能为安装任务创建配置快照");
        }
        if (!job.getCluster().getId().equals(cluster.getId())) {
            throw new IllegalArgumentException("安装快照所属集群不匹配");
        }
        InstallationSnapshotPayload payload = InstallationSnapshotPayload.capture(cluster, nodes);
        try {
            snapshots.save(new InstallationSnapshot(job, cluster, mapper.writeValueAsString(payload)));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("安装配置快照序列化失败", exception);
        }
    }

    @Transactional(readOnly = true)
    public InstallationSnapshotPayload latestInstallPayload(long clusterId) {
        InstallationSnapshot snapshot = snapshots
                .findTopByCluster_IdAndJob_TypeOrderByIdDesc(clusterId, "install")
                .orElseThrow(() -> new IllegalArgumentException("集群没有可用于远程重置的安装快照"));
        try {
            return mapper.readValue(snapshot.getSnapshotJson(), InstallationSnapshotPayload.class);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("安装配置快照无法读取", exception);
        }
    }
}
