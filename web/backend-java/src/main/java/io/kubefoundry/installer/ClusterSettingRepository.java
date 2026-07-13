package io.kubefoundry.installer;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ClusterSettingRepository extends JpaRepository<ClusterSetting, Long> {
    List<ClusterSetting> findByClusterIdOrderByKey(long clusterId);
    Optional<ClusterSetting> findByClusterIdAndKey(long clusterId, String key);
}
