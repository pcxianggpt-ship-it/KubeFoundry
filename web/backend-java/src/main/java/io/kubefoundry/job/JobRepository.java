package io.kubefoundry.job;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface JobRepository extends JpaRepository<Job, Long> {
    List<Job> findAllByOrderByIdDesc();
    List<Job> findByClusterIdOrderByIdDesc(long clusterId);
    Optional<Job> findFirstByClusterIdAndTypeAndStatusInOrderByIdDesc(
            long clusterId, String type, List<String> statuses);
    Optional<Job> findFirstByClusterIdAndTypeInAndStatusInOrderByIdDesc(
            long clusterId, List<String> types, List<String> statuses);
    List<Job> findByTypeAndStatusIn(String type, List<String> statuses);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("update Job job set job.status = 'interrupted' where job.status = :status")
    int replaceStatus(@Param("status") String status);
}
