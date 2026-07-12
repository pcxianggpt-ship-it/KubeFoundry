package io.kubefoundry.job;

import java.util.List;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface JobStepNodeRepository extends JpaRepository<JobStepNode, Long> {
    @EntityGraph(attributePaths = "node")
    List<JobStepNode> findByStepIdOrderById(long stepId);
}
