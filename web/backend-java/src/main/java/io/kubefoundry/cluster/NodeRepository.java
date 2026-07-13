package io.kubefoundry.cluster;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface NodeRepository extends JpaRepository<Node, Long> {
    List<Node> findByClusterIdOrderById(long clusterId);
    Optional<Node> findByIdAndClusterId(long id, long clusterId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            update nodes
               set host_fingerprint = coalesce(host_fingerprint, :fingerprint)
             where id = :nodeId
               and (host_fingerprint is null or host_fingerprint = :fingerprint)
               and cluster_id in (
                   select id from clusters where node_config_version = :expectedVersion)
            """, nativeQuery = true)
    int recordHostFingerprintIfConfigurationUnchanged(
            @Param("nodeId") long nodeId,
            @Param("expectedVersion") long expectedVersion,
            @Param("fingerprint") String fingerprint);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            update nodes
               set node_test_status = :phase, node_test_message = null
             where id = :nodeId
               and cluster_id in (
                   select id from clusters where node_config_version = :expectedVersion)
            """, nativeQuery = true)
    int updateTestPhaseIfConfigurationUnchanged(
            @Param("nodeId") long nodeId,
            @Param("expectedVersion") long expectedVersion,
            @Param("phase") String phase);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            update nodes
               set node_test_status = 'success', node_test_message = '测试成功',
                   os_type = :osType, os_version = :osVersion, architecture = :architecture
             where id = :nodeId
               and cluster_id in (
                   select id from clusters where node_config_version = :expectedVersion)
            """, nativeQuery = true)
    int completeTestIfConfigurationUnchanged(
            @Param("nodeId") long nodeId,
            @Param("expectedVersion") long expectedVersion,
            @Param("osType") String osType,
            @Param("osVersion") String osVersion,
            @Param("architecture") String architecture);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            update nodes
               set node_test_status = 'failed', node_test_message = :message,
                   os_type = null, os_version = null, architecture = null
             where id = :nodeId
               and cluster_id in (
                   select id from clusters where node_config_version = :expectedVersion)
            """, nativeQuery = true)
    int failTestIfConfigurationUnchanged(
            @Param("nodeId") long nodeId,
            @Param("expectedVersion") long expectedVersion,
            @Param("message") String message);
}
