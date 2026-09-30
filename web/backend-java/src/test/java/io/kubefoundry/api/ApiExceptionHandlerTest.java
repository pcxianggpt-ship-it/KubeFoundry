package io.kubefoundry.api;

import io.kubefoundry.installer.MinioWorkerCountException;
import java.util.Map;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ApiExceptionHandlerTest {

    @Test
    void returnsStableMinioWorkerCountConflictWithoutExtraDetails() {
        var response = new ApiExceptionHandler().minioWorkerCount(new MinioWorkerCountException(3));

        assertThat(response.getStatusCode().value()).isEqualTo(409);
        assertThat(response.getBody()).containsEntry("code", "MINIO_WORKER_COUNT_INSUFFICIENT");
        assertThat(response.getBody().get("details")).isEqualTo(Map.of(
                "required_workers", 4,
                "actual_workers", 3));
    }
}
