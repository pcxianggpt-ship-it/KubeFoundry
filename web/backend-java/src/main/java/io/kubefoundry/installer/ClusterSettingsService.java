package io.kubefoundry.installer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ClusterConfigurationLockedException;
import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.Node;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClusterSettingsService {

    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {};

    private final ClusterRepository clusters;
    private final ClusterSettingRepository settings;
    private final AppSettingRepository appSettings;
    private final ObjectMapper objectMapper;
    private final String appDirectory;
    private final InstallerAdmission admission;

    public ClusterSettingsService(
            ClusterRepository clusters,
            ClusterSettingRepository settings,
            AppSettingRepository appSettings,
            ObjectMapper objectMapper,
            @Value("${kubefoundry.app-dir}") String appDirectory,
            InstallerAdmission admission) {
        this.clusters = clusters;
        this.settings = settings;
        this.appSettings = appSettings;
        this.objectMapper = objectMapper;
        this.appDirectory = java.nio.file.Path.of(appDirectory).toAbsolutePath().normalize().toString();
        this.admission = admission;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getGlobalSettings() {
        return publicSettings(globalSettings());
    }

    @Transactional
    public Map<String, Object> updateGlobalSettings(Map<String, Object> incoming) {
        validateIncoming(incoming);
        saveAppSettings(incoming);
        return publicSettings(globalSettings());
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getClusterSettings(long clusterId) {
        requireCluster(clusterId);
        return publicSettings(mergedSettings(clusterId));
    }

    @Transactional
    public Map<String, Object> updateClusterSettings(long clusterId, Map<String, Object> incoming) {
        Cluster cluster = requireCluster(clusterId);
        admission.requireConfigurationWritable(clusterId, cluster.isInstallationLocked());
        if (incoming == null) return mergedSettings(clusterId);
        validateIncoming(incoming);
        for (Map.Entry<String, Object> entry : incoming.entrySet()) {
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
        Map<String, Object> result = globalSettings();
        for (ClusterSetting setting : settings.findByClusterIdOrderByKey(clusterId)) {
            mergeStoredSetting(result, setting.getKey(), decode(setting.getValue()));
        }
        return result;
    }

    private Map<String, Object> globalSettings() {
        Map<String, Object> result = defaults();
        for (AppSetting setting : appSettings.findAllByOrderByKeyAsc()) {
            mergeStoredSetting(result, setting.getKey(), decode(setting.getValue()));
        }
        return result;
    }

    private void saveAppSettings(Map<String, Object> incoming) {
        for (Map.Entry<String, Object> entry : incoming.entrySet()) {
            String serialized = serialize(entry.getValue());
            AppSetting setting = appSettings.findById(entry.getKey())
                    .orElseGet(() -> new AppSetting(entry.getKey(), serialized));
            setting.updateValue(serialized);
            appSettings.save(setting);
        }
        appSettings.flush();
    }

    private void mergeStoredSetting(Map<String, Object> target, String key, Object value) {
        if (!allowedGroups().contains(key) || !(value instanceof Map<?, ?> raw)) return;
        Map<String, Object> permitted;
        try {
            permitted = permittedGroup(key, raw);
        } catch (IllegalArgumentException ignored) {
            return;
        }
        if (permitted.isEmpty()) return;
        Map<String, Object> merged = group(target, key);
        merged.putAll(permitted);
        target.put(key, merged);
    }

    private static void validateIncoming(Map<String, Object> incoming) {
        if (incoming == null) throw new IllegalArgumentException("设置内容不能为空");
        for (Map.Entry<String, Object> entry : incoming.entrySet()) {
            String key = entry.getKey();
            rejectSensitiveKey(key);
            rejectSensitiveKeys(entry.getValue());
            if (!allowedGroups().contains(key)) {
                throw new IllegalArgumentException("不允许的设置项: " + key);
            }
            if (!(entry.getValue() instanceof Map<?, ?> raw)) {
                throw new IllegalArgumentException("设置分组必须是对象: " + key);
            }
            Map<String, Object> permitted = permittedGroup(key, raw);
            if (permitted.size() != raw.size()) {
                throw new IllegalArgumentException("设置包含未知或无效子项: " + key);
            }
        }
    }

    private static Map<String, Object> permittedGroup(String group, Map<?, ?> raw) {
        Map<String, Object> permitted = new LinkedHashMap<>();
        Set<String> allowed = allowedKeys(group);
        for (Map.Entry<?, ?> entry : raw.entrySet()) {
            if (!(entry.getKey() instanceof String key)) continue;
            rejectSensitiveKey(key);
            if (!allowed.contains(key)) continue;
            Object value = entry.getValue();
            boolean valid = "advanced".equals(group)
                    ? value instanceof Boolean
                    : value instanceof String;
            if (valid) permitted.put(key, value);
        }
        return permitted;
    }

    private static Set<String> allowedGroups() {
        return Set.of("paths", "env", "advanced");
    }

    private static Set<String> allowedKeys(String group) {
        return switch (group) {
            case "paths" -> Set.of("k8s_home", "install_media", "arch", "repo_source",
                    "kubeadm_100y", "container_runtime", "registry_install", "flannel_config");
            case "env" -> Set.of("kubelet_root", "containerd_root", "etcd_data_dir");
            case "advanced" -> Set.of("enable_ipv6_dual_stack");
            default -> Set.of();
        };
    }

    private static void rejectSensitiveKey(String key) {
        String value = key == null ? "" : key.toLowerCase(java.util.Locale.ROOT);
        for (String forbidden : Set.of("password", "passphrase", "private_key", "secret", "token", "credential")) {
            if (value.contains(forbidden)) {
                throw new IllegalArgumentException("不允许敏感设置项: " + key);
            }
        }
    }

    private static void rejectSensitiveKeys(Object value) {
        if (!(value instanceof Map<?, ?> map)) return;
        for (Map.Entry<?, ?> entry : map.entrySet()) {
            if (entry.getKey() instanceof String key) rejectSensitiveKey(key);
            rejectSensitiveKeys(entry.getValue());
        }
    }

    private Map<String, Object> defaults() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("paths", new LinkedHashMap<>(Map.ofEntries(
                Map.entry("k8s_home", "/data/k8s_install"),
                Map.entry("install_media", java.nio.file.Path.of(appDirectory, "kube-media").toString()),
                Map.entry("arch", "amd64"),
                Map.entry("repo_source", "${install_media}/01.rpm_package/k8srepo_kylinos_sp3_${arch}.tar.gz"),
                Map.entry("kubeadm_100y", "${install_media}/01.rpm_package/kubeadm-v${k8s_version}-100y-${arch}"),
                Map.entry("container_runtime", "${install_media}/02.container_runtime"),
                Map.entry("registry_install", "${install_media}/04.registry"),
                Map.entry("flannel_config", "${install_media}/03.setup_file/kube-flannel.yml"))));
        result.put("env", new LinkedHashMap<>(Map.of(
                "kubelet_root", "${k8s_home}/kubelet_root",
                "containerd_root", "${k8s_home}/containerd_root",
                "etcd_data_dir", "${k8s_home}/etcd_root")));
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
