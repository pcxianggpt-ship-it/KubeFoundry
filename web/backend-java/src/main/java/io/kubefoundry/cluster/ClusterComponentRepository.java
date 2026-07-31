package io.kubefoundry.cluster;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;

public interface ClusterComponentRepository extends JpaRepository<ClusterComponent, Long> {
    List<ClusterComponent> findByClusterIdOrderByComponentKey(long clusterId);
    Optional<ClusterComponent> findByClusterIdAndComponentKey(long clusterId, String componentKey);
    @Transactional
    void deleteByClusterId(long clusterId);
}
