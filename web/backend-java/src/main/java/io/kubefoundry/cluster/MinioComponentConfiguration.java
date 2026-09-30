package io.kubefoundry.cluster;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** MinIO 资源配置的唯一白名单、默认值和 Quantity 校验入口。 */
public final class MinioComponentConfiguration {
    public static final String GROUP_KEY = "storage_observability";
    public static final Map<String, String> DEFAULTS = Map.of(
            "minio_pvc_size", "10Gi",
            "minio_cpu_request", "250m",
            "minio_cpu_limit", "2",
            "minio_memory_request", "512Mi",
            "minio_memory_limit", "4Gi");
    public static final Set<String> FIELDS = DEFAULTS.keySet();

    private static final Pattern CPU = Pattern.compile("^([0-9]+(?:\\.[0-9]+)?)(m)?$");
    private static final Pattern BYTES = Pattern.compile("^([0-9]+(?:\\.[0-9]+)?)(Ki|Mi|Gi|Ti|Pi|Ei)?$");

    private MinioComponentConfiguration() { }

    public static Map<String, Object> validate(Map<String, Object> config) {
        Map<String, Object> supplied = config == null ? Map.of() : config;
        if (!FIELDS.containsAll(supplied.keySet())) {
            throw invalid("MinIO 配置包含未知字段");
        }
        Map<String, Object> values = new LinkedHashMap<>(DEFAULTS);
        values.putAll(supplied);
        values.replaceAll((key, value) -> requireString(key, value));

        BigDecimal pvc = bytes(values.get("minio_pvc_size").toString(), "minio_pvc_size");
        BigDecimal cpuRequest = cpu(values.get("minio_cpu_request").toString(), "minio_cpu_request");
        BigDecimal cpuLimit = cpu(values.get("minio_cpu_limit").toString(), "minio_cpu_limit");
        BigDecimal memoryRequest = bytes(values.get("minio_memory_request").toString(), "minio_memory_request");
        BigDecimal memoryLimit = bytes(values.get("minio_memory_limit").toString(), "minio_memory_limit");
        if (pvc.signum() <= 0) throw invalid("MinIO minio_pvc_size 必须大于 0");
        if (cpuRequest.signum() <= 0 || cpuLimit.signum() <= 0) {
            throw invalid("MinIO CPU request/limit 必须大于 0");
        }
        if (memoryRequest.signum() <= 0 || memoryLimit.signum() <= 0) {
            throw invalid("MinIO 内存 request/limit 必须大于 0");
        }
        if (cpuRequest.compareTo(cpuLimit) > 0) throw invalid("MinIO CPU request 不能大于 limit");
        if (memoryRequest.compareTo(memoryLimit) > 0) throw invalid("MinIO 内存 request 不能大于 limit");
        return Map.copyOf(values);
    }

    public static Map<String, String> environment(Map<String, Object> config) {
        Map<String, Object> values = validate(config);
        return Map.of(
                "minio_pvc_size", values.get("minio_pvc_size").toString(),
                "minio_cpu_request", values.get("minio_cpu_request").toString(),
                "minio_cpu_limit", values.get("minio_cpu_limit").toString(),
                "minio_memory_request", values.get("minio_memory_request").toString(),
                "minio_memory_limit", values.get("minio_memory_limit").toString());
    }

    private static String requireString(String field, Object value) {
        if (!(value instanceof String text) || text.isBlank()) {
            throw invalid("MinIO " + field + " 必须是非空字符串");
        }
        return text.trim();
    }

    private static BigDecimal cpu(String value, String field) {
        Matcher matcher = CPU.matcher(value);
        if (!matcher.matches()) throw invalid("MinIO " + field + " 不是有效的 Kubernetes CPU Quantity");
        BigDecimal amount = new BigDecimal(matcher.group(1));
        return matcher.group(2) == null ? amount : amount.movePointLeft(3);
    }

    private static BigDecimal bytes(String value, String field) {
        Matcher matcher = BYTES.matcher(value);
        if (!matcher.matches()) throw invalid("MinIO " + field + " 不是有效的 Kubernetes 容量 Quantity");
        BigDecimal amount = new BigDecimal(matcher.group(1));
        String suffix = matcher.group(2);
        if (suffix == null) return amount;
        int power = switch (suffix) {
            case "Ki" -> 1;
            case "Mi" -> 2;
            case "Gi" -> 3;
            case "Ti" -> 4;
            case "Pi" -> 5;
            case "Ei" -> 6;
            default -> 0;
        };
        return amount.multiply(BigDecimal.valueOf(1024).pow(power));
    }

    private static ClusterComponentService.ComponentConfigurationException invalid(String message) {
        return new ClusterComponentService.ComponentConfigurationException("COMPONENT_CONFIG_INVALID", message);
    }
}
