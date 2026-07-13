package io.kubefoundry.installer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.Node;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClusterSettingsService {

    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {};

    private final ClusterRepository clusters;
    private final ClusterSettingRepository settings;
    private final ObjectMapper objectMapper;

    public ClusterSettingsService(
            ClusterRepository clusters,
            ClusterSettingRepository settings,
            ObjectMapper objectMapper) {
        this.clusters = clusters;
        this.settings = settings;
        this.objectMapper = objectMapper;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getGlobalSettings() {
        return publicSettings(defaults());
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getClusterSettings(long clusterId) {
        requireCluster(clusterId);
        return publicSettings(mergedSettings(clusterId));
    }

    @Transactional
    public Map<String, Object> updateClusterSettings(long clusterId, Map<String, Object> incoming) {
        Cluster cluster = requireCluster(clusterId);
        if (incoming == null) return mergedSettings(clusterId);
        for (Map.Entry<String, Object> entry : incoming.entrySet()) {
            if (entry.getKey() == null || entry.getKey().isBlank()) continue;
            String serialized = serialize(entry.getValue());
            ClusterSetting setting = settings.findByClusterIdAndKey(clusterId, entry.getKey())
                    .orElseGet(() -> new ClusterSetting(cluster, entry.getKey(), serialized));
            setting.updateValue(serialized);
            settings.save(setting);
        }
        settings.flush();
        return publicSettings(mergedSettings(clusterId));
    }

    @Transactional(readOnly = true)
    public RuntimeSettings runtimeSettings(Cluster cluster, Node node) {
        Map<String, Object> merged = mergedSettings(cluster.getId());
        Map<String, String> paths = stringMap(group(merged, "paths"));
        Map<String, String> env = stringMap(group(merged, "env"));
        Map<String, Object> advanced = group(merged, "advanced");

        String arch = value(node.getArchitecture(), paths.getOrDefault("arch", "amd64"));
        paths.put("arch", arch);
        Map<String, String> variables = new LinkedHashMap<>(paths);
        variables.put("k8s_version", value(cluster.getKubernetesVersion(), ""));
        variables.put("arch", arch);
        expandInPlace(paths, variables);
        variables.putAll(paths);

        // Python compatibility: historical UI stored kubelet/etcd roots under
        // paths. Prefer env, but honor those path overrides if env is absent.
        copyLegacyEnv(paths, env, "kubelet_root");
        copyLegacyEnv(paths, env, "containerd_root");
        copyLegacyEnv(paths, env, "etcd_data_dir");
        expandInPlace(env, variables);
        return new RuntimeSettings(paths, env, advanced);
    }

    private Cluster requireCluster(long clusterId) {
        return clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
    }

    private Map<String, Object> mergedSettings(long clusterId) {
        Map<String, Object> result = defaults();
        for (ClusterSetting setting : settings.findByClusterIdOrderByKey(clusterId)) {
            Object decoded = decode(setting.getValue());
            if (decoded instanceof Map<?, ?> decodedMap
                    && result.get(setting.getKey()) instanceof Map<?, ?> currentMap) {
                Map<String, Object> merged = new LinkedHashMap<>();
                currentMap.forEach((key, value) -> {
                    if (key != null) merged.put(key.toString(), value);
                });
                decodedMap.forEach((key, value) -> {
                    if (key != null) merged.put(key.toString(), value);
                });
                result.put(setting.getKey(), merged);
            } else {
                result.put(setting.getKey(), decoded);
            }
        }
        return result;
    }

    private Map<String, Object> defaults() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("paths", new LinkedHashMap<>(Map.ofEntries(
                Map.entry("k8s_home", "/data/k8s_install"),
                Map.entry("install_media", "/root/kube-media"),
                Map.entry("arch", "amd64"),
                Map.entry("repo_source", "${install_media}/01.rpm_package/k8srepo_kylinos_sp3_${arch}.tar.gz"),
                Map.entry("kubeadm_100y", "${install_media}/01.rpm_package/kubeadm-v${k8s_version}-100y-${arch}"),
                Map.entry("container_runtime", "${install_media}/02.container_runtime"),
                Map.entry("registry_install", "${install_media}/04.registry"),
                Map.entry("flannel_config", "${install_media}/03.setup_file/kube-flannel.yml"))));
        result.put("env", new LinkedHashMap<>(Map.of(
                "kubelet_root", "${k8s_home}/kubelet_root",
                "containerd_root", "${k8s_home}/containerd-data",
                "etcd_data_dir", "${k8s_home}/etcd_backup")));
        result.put("advanced", new LinkedHashMap<>(Map.of(
                "enable_ipv6_dual_stack", false)));
        return result;
    }

    private static Map<String, Object> publicSettings(Map<String, Object> settings) {
        Map<String, Object> result = new LinkedHashMap<>(settings);
        Map<String, Object> paths = group(result, "paths");
        Map<String, String> env = stringMap(group(result, "env"));
        Map<String, String> variables = stringMap(paths);
        expandInPlace(env, variables);
        result.put("paths", paths);
        result.put("env", new LinkedHashMap<>(env));
        return result;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> group(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value instanceof Map<?, ?> map) {
            Map<String, Object> result = new LinkedHashMap<>();
            map.forEach((itemKey, itemValue) -> {
                if (itemKey != null) result.put(itemKey.toString(), itemValue);
            });
            return result;
        }
        return new LinkedHashMap<>();
    }

    private static Map<String, String> stringMap(Map<String, Object> data) {
        Map<String, String> result = new LinkedHashMap<>();
        data.forEach((key, value) -> {
            if (value != null) result.put(key, value.toString());
        });
        return result;
    }

    private Object decode(String value) {
        if (value == null || value.isBlank()) return "";
        try {
            return objectMapper.readValue(value, MAP_TYPE);
        } catch (JsonProcessingException ignored) {
            return value;
        }
    }

    private String serialize(Object value) {
        if (value == null) return "";
        if (value instanceof String text) return text;
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("设置内容无法序列化");
        }
    }

    private static void copyLegacyEnv(
            Map<String, String> paths, Map<String, String> env, String key) {
        if (!env.containsKey(key) && paths.containsKey(key)) {
            env.put(key, paths.get(key));
        }
    }

    private static void expandInPlace(Map<String, String> data, Map<String, String> variables) {
        for (int pass = 0; pass < 3; pass++) {
            data.replaceAll((key, value) -> expand(value, variables));
            variables.putAll(data);
        }
    }

    private static String expand(String value, Map<String, String> variables) {
        if (value == null) return "";
        String result = value;
        for (Map.Entry<String, String> entry : variables.entrySet()) {
            result = result.replace("${" + entry.getKey() + "}", value(entry.getValue(), ""));
        }
        return result;
    }

    private static String value(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
