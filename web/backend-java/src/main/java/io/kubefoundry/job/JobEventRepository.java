package io.kubefoundry.job;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface JobEventRepository extends JpaRepository<JobEvent, Long> {
    List<JobEvent> findTop100ByJobIdAndIdGreaterThanOrderById(long jobId, long afterId);
}
