package io.kubefoundry.installer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterComponent;
import io.kubefoundry.cluster.ClusterComponentRepository;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InstallationSnapshotService {

    private final InstallationSnapshotRepository snapshots;
    private final JobRepository jobs;
    private final ClusterComponentRepository components;
    private final ObjectMapper mapper;
    private final ClusterSettingsService settings;

    @Autowired
    public InstallationSnapshotService(
            InstallationSnapshotRepository snapshots,
            JobRepository jobs,
            ClusterComponentRepository components,
            ObjectMapper mapper,
            ClusterSettingsService settings) {
        this.snapshots = snapshots;
        this.jobs = jobs;
        this.components = components;
        this.mapper = mapper;
        this.settings = settings;
    }

    InstallationSnapshotService(
            InstallationSnapshotRepository snapshots,
            JobRepository jobs,
            ClusterComponentRepository components,
            ObjectMapper mapper) {
        this(snapshots, jobs, components, mapper, null);
    }

    @Transactional
    public void capture(long jobId, Cluster cluster, List<Node> nodes) {
        capture(jobId, cluster, nodes, java.util.Map.of());
    }

    @Transactional
    public void capture(long jobId, Cluster cluster, List<Node> nodes, java.util.Map<String, String> mediaChecksums) {
        Job job = jobs.findById(jobId)
                .orElseThrow(() -> new IllegalArgumentException("安装任务不存在: " + jobId));
        if (!"install".equals(job.getType())
                && !ComponentInstallationStateService.JOB_TYPE.equals(job.getType())) {
            throw new IllegalArgumentException("只能为安装或组件安装任务创建配置快照");
        }
        if (!job.getCluster().getId().equals(cluster.getId())) {
            throw new IllegalArgumentException("安装快照所属集群不匹配");
        }
        InstallationSnapshotPayload payload = withRuntimeSettings(
                InstallationSnapshotPayload.capture(
                        cluster, nodes, componentGroups(cluster.getId()), mediaChecksums),
                cluster, nodes);
        try {
            snapshots.save(new InstallationSnapshot(job, cluster, mapper.writeValueAsString(payload)));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("安装配置快照序列化失败", exception);
        }
    }

    private List<InstallationSnapshotPayload.ComponentGroup> componentGroups(long clusterId) {
        return components.findByClusterIdOrderByComponentKey(clusterId).stream()
                .map(component -> new InstallationSnapshotPayload.ComponentGroup(
                        component.getComponentKey(), component.isEnabled(), parseConfig(component)))
                .toList();
    }

    @Transactional(readOnly = true)
    public InstallationSnapshotPayload previewPayload(Cluster cluster, List<Node> nodes) {
        if (cluster == null || cluster.getId() == null) {
            throw new IllegalArgumentException("安装计划缺少集群");
        }
        return withRuntimeSettings(InstallationSnapshotPayload.capture(
                cluster, nodes, componentGroups(cluster.getId()), java.util.Map.of()), cluster, nodes);
    }

    private InstallationSnapshotPayload withRuntimeSettings(
            InstallationSnapshotPayload payload, Cluster cluster, List<Node> nodes) {
        if (settings == null) return payload;
        Map<Long, InstallationSnapshotPayload.RuntimeConfiguration> values = new TreeMap<>();
        for (Node node : InstallationNodes.normalize(nodes)) {
            values.put(node.getId(), InstallationSnapshotPayload.RuntimeConfiguration.from(
                    settings.runtimeSettings(cluster, node)));
        }
        return payload.withRuntimeSettings(values);
    }

    @Transactional(readOnly = true)
    public InstallationSnapshotPayload payloadForJob(long jobId) {
        InstallationSnapshot snapshot = snapshots.findByJobId(jobId)
                .orElseThrow(() -> new InstallResumeException(
                        "RESUME_SNAPSHOT_MISMATCH", "来源任务没有完整安装快照"));
        return readPayload(snapshot);
    }

    @Transactional
    public void copyForResume(long sourceJobId, long targetJobId) {
        InstallationSnapshot source = snapshots.findByJobId(sourceJobId)
                .orElseThrow(() -> new InstallResumeException(
                        "RESUME_SNAPSHOT_MISMATCH", "来源任务没有完整安装快照"));
        Job target = jobs.findById(targetJobId)
                .orElseThrow(() -> new IllegalArgumentException("续跑任务不存在: " + targetJobId));
        if (!source.getCluster().getId().equals(target.getCluster().getId())) {
            throw new InstallResumeException(
                    "RESUME_SOURCE_NOT_SUPPORTED", "来源任务不属于当前集群");
        }
        snapshots.save(new InstallationSnapshot(
                target, target.getCluster(), source.getSnapshotJson()));
    }

    private java.util.Map<String, Object> parseConfig(ClusterComponent component) {
        try {
            return mapper.readValue(component.getConfigJson(), new TypeReference<java.util.Map<String, Object>>() { });
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("组件配置无法写入安装快照: " + component.getComponentKey(), exception);
        }
    }

    @Transactional(readOnly = true)
    public InstallationSnapshotPayload latestInstallPayload(long clusterId) {
        InstallationSnapshot snapshot = snapshots
                .findTopByCluster_IdAndJob_TypeOrderByIdDesc(clusterId, "install")
                .orElseThrow(() -> new IllegalArgumentException("集群没有可用于远程重置的安装快照"));
        InstallationSnapshotPayload installPayload = readPayload(snapshot);
        Map<String, String> mediaChecksums = new LinkedHashMap<>();
        for (InstallationSnapshot componentSnapshot : snapshots
                .findByCluster_IdAndJob_TypeAndJob_StatusOrderByIdDesc(
                        clusterId, ComponentInstallationStateService.JOB_TYPE, "success")) {
            readPayload(componentSnapshot).mediaChecksums()
                    .forEach(mediaChecksums::putIfAbsent);
        }
        installPayload.mediaChecksums().forEach(mediaChecksums::putIfAbsent);
        return new InstallationSnapshotPayload(
                installPayload.clusterId(),
                installPayload.clusterName(),
                installPayload.kubernetesVersion(),
                installPayload.kubernetesWorkDir(),
                installPayload.imageRegistryType(),
                installPayload.nodes(),
                installPayload.componentConfigurationVersion(),
                installPayload.componentGroups(),
                installPayload.componentPlanVersion(),
                mediaChecksums,
                installPayload.clusterConfiguration(),
                installPayload.runtimeSettings());
    }

    private InstallationSnapshotPayload readPayload(InstallationSnapshot snapshot) {
        try {
            return mapper.readValue(snapshot.getSnapshotJson(), InstallationSnapshotPayload.class);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("安装配置快照无法读取", exception);
        }
    }
}
