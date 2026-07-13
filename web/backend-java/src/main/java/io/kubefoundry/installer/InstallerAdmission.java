package io.kubefoundry.installer;

import io.kubefoundry.job.JobRepository;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.function.LongSupplier;
import org.springframework.stereotype.Component;

@Component
public class InstallerAdmission {

    private static final List<String> INSTALLER_TYPES = List.of("install", "precheck");
    private static final List<String> ACTIVE_STATUSES = List.of("pending", "running");

    private final JobRepository jobs;
    private final ConcurrentMap<Long, Object> locks = new ConcurrentHashMap<>();

    public InstallerAdmission(JobRepository jobs) {
        this.jobs = jobs;
    }

    public long submit(long clusterId, LongSupplier submitter) {
        synchronized (locks.computeIfAbsent(clusterId, ignored -> new Object())) {
            jobs.findFirstByClusterIdAndTypeInAndStatusInOrderByIdDesc(
                    clusterId, INSTALLER_TYPES, ACTIVE_STATUSES)
                    .ifPresent(job -> {
                        throw new ActiveInstallerJobException(job.getType(), job.getId());
                    });
            return submitter.getAsLong();
        }
    }
}
