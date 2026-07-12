package io.kubefoundry.cluster;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface NodeRepository extends JpaRepository<Node, Long> {
    List<Node> findByClusterIdOrderById(long clusterId);
}
