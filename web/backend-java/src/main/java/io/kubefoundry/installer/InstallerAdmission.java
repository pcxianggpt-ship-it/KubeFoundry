package io.kubefoundry.installer;

import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ClusterConfigurationLockedException;
import io.kubefoundry.job.JobRepository;
import java.util.List;
import java.util.function.LongSupplier;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

@Component
public class InstallerAdmission {

    private static final List<String> INSTALLER_TYPES = List.of(
            "install", ComponentInstallationStateService.JOB_TYPE, "precheck", "reset");
    private static final List<String> ACTIVE_STATUSES = List.of("pending", "running");

    private final ClusterRepository clusters;
    private final JobRepository jobs;
    private final TransactionTemplate transactions;

    public InstallerAdmission(
            ClusterRepository clusters, JobRepository jobs, TransactionTemplate transactions) {
        this.clusters = clusters;
        this.jobs = jobs;
        this.transactions = transactions;
    }

    public long submit(long clusterId, LongSupplier submitter) {
        Long jobId = transactions.execute(status -> {
            clusters.findByIdForUpdate(clusterId)
                    .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
            jobs.findFirstByClusterIdAndTypeInAndStatusInOrderByIdDesc(
                    clusterId, INSTALLER_TYPES, ACTIVE_STATUSES)
                    .ifPresent(job -> {
                        throw new ActiveInstallerJobException(job.getType(), job.getId());
                    });
            return submitter.getAsLong();
        });
        if (jobId == null) throw new IllegalStateException("安装任务准入未返回任务 ID");
        return jobId;
    }

    public void requireConfigurationWritable(long clusterId, boolean installationLocked) {
        requireNoActiveInstallerJob(clusterId);
        if (installationLocked) {
            throw new ClusterConfigurationLockedException("安装成功后必须先完成远程重置，才能修改集群配置");
        }
    }

    /**
     * 组件配置在基础集群安装完成后仍可调整，但不能与安装、预检查或重置并发。
     */
    public void requireNoActiveInstallerJob(long clusterId) {
        transactions.executeWithoutResult(status -> {
            clusters.findByIdForUpdate(clusterId)
                    .orElseThrow(() -> new IllegalArgumentException("集群不存在: " + clusterId));
            jobs.findFirstByClusterIdAndTypeInAndStatusInOrderByIdDesc(
                    clusterId, INSTALLER_TYPES, ACTIVE_STATUSES)
                    .ifPresent(job -> {
                        throw new ActiveInstallerJobException(job.getType(), job.getId());
                    });
        });
    }

}
