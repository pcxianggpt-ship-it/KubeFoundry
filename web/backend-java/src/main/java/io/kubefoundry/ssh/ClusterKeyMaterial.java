package io.kubefoundry.ssh;

import java.security.KeyPair;

public record ClusterKeyMaterial(String authorizedKey, KeyPair keyPair) {
}
