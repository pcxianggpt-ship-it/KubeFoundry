package io.kubefoundry.installer;

import io.kubefoundry.cluster.MinioComponentConfiguration;

public final class MinioInstallationAdmission {
    private MinioInstallationAdmission() { }

    public static void requireEnoughWorkers(InstallationSnapshotPayload snapshot) {
        boolean enabled = snapshot.componentGroups().stream().anyMatch(group ->
                MinioComponentConfiguration.GROUP_KEY.equals(group.key()) && group.enabled());
        if (!enabled) return;
        int workers = (int) snapshot.nodes().stream()
                .filter(node -> node.roles().contains("worker"))
                .count();
        if (workers < MinioWorkerCountException.REQUIRED_WORKERS) {
            throw new MinioWorkerCountException(workers);
        }
    }
}
