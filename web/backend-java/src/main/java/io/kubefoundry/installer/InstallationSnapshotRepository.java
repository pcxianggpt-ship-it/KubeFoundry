package io.kubefoundry.installer;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface InstallationSnapshotRepository extends JpaRepository<InstallationSnapshot, Long> {
    Optional<InstallationSnapshot> findByJobId(long jobId);
    Optional<InstallationSnapshot> findTopByCluster_IdAndJob_TypeOrderByIdDesc(long clusterId, String type);
    List<InstallationSnapshot> findByCluster_IdAndJob_TypeAndJob_StatusOrderByIdDesc(
            long clusterId, String type, String status);
}
