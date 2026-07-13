package io.kubefoundry.cluster;

import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface ClusterRepository extends JpaRepository<Cluster, Long> {
    Optional<Cluster> findByName(String name);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select cluster from Cluster cluster where cluster.id = :clusterId")
    Optional<Cluster> findByIdForUpdate(@Param("clusterId") long clusterId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("update Cluster cluster set cluster.nodeConfigVersion = cluster.nodeConfigVersion + 1, "
            + "cluster.nodeTestStatus = 'stale' where cluster.id = :clusterId")
    int markNodeConfigurationChanged(@Param("clusterId") long clusterId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("update Cluster cluster set cluster.nodeTestStatus = :status "
            + "where cluster.id = :clusterId "
            + "and cluster.nodeConfigVersion = :expectedVersion")
    int updateNodeTestStatusIfConfigurationUnchanged(
            @Param("clusterId") long clusterId,
            @Param("expectedVersion") long expectedVersion,
            @Param("status") String status);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            update clusters
               set node_test_status = case
                   when exists (
                       select 1 from nodes node
                        where node.cluster_id = clusters.id
                          and node.node_test_status = 'failed') then 'failed'
                   when exists (
                       select 1 from nodes node
                        where node.cluster_id = clusters.id)
                    and not exists (
                       select 1 from nodes node
                        where node.cluster_id = clusters.id
                          and node.node_test_status <> 'success') then 'success'
                   else 'running'
               end
             where id = :clusterId
               and node_config_version = :expectedVersion
            """, nativeQuery = true)
    int refreshNodeTestAggregate(
            @Param("clusterId") long clusterId,
            @Param("expectedVersion") long expectedVersion);
}
