package io.kubefoundry.cluster;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ClusterComponentStateRepository extends JpaRepository<ClusterComponentState, Long> {
    List<ClusterComponentState> findByClusterIdOrderByComponentKey(long clusterId);
    Optional<ClusterComponentState> findByClusterIdAndComponentKey(long clusterId, String componentKey);
}
