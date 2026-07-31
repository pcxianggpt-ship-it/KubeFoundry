package io.kubefoundry.installer;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface InstallationSnapshotRepository extends JpaRepository<InstallationSnapshot, Long> {
    Optional<InstallationSnapshot> findByJobId(long jobId);
    Optional<InstallationSnapshot> findTopByCluster_IdAndJob_TypeOrderByIdDesc(long clusterId, String type);
}
