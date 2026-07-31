package io.kubefoundry.cluster;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface NodeRoleRepository extends JpaRepository<NodeRole, Long> {
    List<NodeRole> findByNodeIdOrderByRole(long nodeId);
}
