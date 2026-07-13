package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.ssh.SshCommandResult;
import io.kubefoundry.ssh.SshSession;

@FunctionalInterface
public interface RemoteSessionProvider {
    SshCommandResult withSession(Cluster cluster, Node node, SessionWork work) throws Exception;

    @FunctionalInterface
    interface SessionWork {
        SshCommandResult apply(SshSession session) throws Exception;
    }
}
