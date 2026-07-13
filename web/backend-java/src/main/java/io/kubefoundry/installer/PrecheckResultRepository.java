package io.kubefoundry.installer;

import java.util.List;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PrecheckResultRepository extends JpaRepository<PrecheckResult, Long> {
    @EntityGraph(attributePaths = {"node", "job", "cluster"})
    List<PrecheckResult> findByJobIdOrderByNodeIdAscIdAsc(long jobId);
}
