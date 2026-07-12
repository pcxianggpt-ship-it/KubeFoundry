package io.kubefoundry.ssh;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SshKeyRepository extends JpaRepository<SshKey, Long> {
    Optional<SshKey> findByClusterIdAndName(long clusterId, String name);
}
