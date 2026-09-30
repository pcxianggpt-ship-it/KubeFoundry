package io.kubefoundry.installer;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatCode;

class MinioInstallationAdmissionTest {

    @Test
    void rejectsEveryWorkerCountBelowFourButAcceptsExactlyFourWithoutReadyChecks() {
        for (int workerCount = 0; workerCount < 4; workerCount++) {
            int actualWorkers = workerCount;
            assertThatThrownBy(() -> MinioInstallationAdmission.requireEnoughWorkers(snapshot(actualWorkers, true)))
                    .isInstanceOf(MinioWorkerCountException.class)
                    .extracting("actualWorkers").isEqualTo(actualWorkers);
        }
        assertThatCode(() -> MinioInstallationAdmission.requireEnoughWorkers(snapshot(4, true)))
                .doesNotThrowAnyException();
    }

    @Test
    void doesNotApplyWorkerCountGateWhenMinioIsDisabled() {
        assertThatCode(() -> MinioInstallationAdmission.requireEnoughWorkers(snapshot(0, false)))
                .doesNotThrowAnyException();
    }

    private InstallationSnapshotPayload snapshot(int workerCount, boolean minioEnabled) {
        List<InstallationSnapshotPayload.NodeTarget> nodes = IntStream.range(0, workerCount)
                .mapToObj(index -> new InstallationSnapshotPayload.NodeTarget(
                        index + 1L, "worker-" + index, "10.0.0." + (index + 1), "root", 22,
                        Set.of("worker"), "amd64", "", "none"))
                .toList();
        return new InstallationSnapshotPayload(
                1L, "cluster", "1.30.14", "/data/k8s", "REGISTRY", nodes, 1L,
                List.of(new InstallationSnapshotPayload.ComponentGroup(
                        "storage_observability", minioEnabled, Map.of())),
                InstallationSnapshotPayload.COMPONENT_PLAN_VERSION, Map.of());
    }
}
