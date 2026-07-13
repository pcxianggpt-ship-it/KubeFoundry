package io.kubefoundry.ssh;

import io.kubefoundry.cluster.Node;

public interface NodeTestRunner {
    NodeProbe test(
            Node node,
            char[] password,
            ClusterKeyMaterial clusterKey,
            PhaseReporter reporter,
            long expectedConfigVersion) throws Exception;

    @FunctionalInterface
    interface PhaseReporter {
        void report(String phase);
    }
}
