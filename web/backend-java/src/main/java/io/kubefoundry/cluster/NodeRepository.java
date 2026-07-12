package io.kubefoundry.cluster;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface NodeRepository extends JpaRepository<Node, Long> {
    List<Node> findByClusterIdOrderById(long clusterId);
    Optional<Node> findByIdAndClusterId(long id, long clusterId);
}
