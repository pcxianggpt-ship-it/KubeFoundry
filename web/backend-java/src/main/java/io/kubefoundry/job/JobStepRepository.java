package io.kubefoundry.job;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface JobStepRepository extends JpaRepository<JobStep, Long> {
    List<JobStep> findByJobIdOrderByOrder(long jobId);
}
