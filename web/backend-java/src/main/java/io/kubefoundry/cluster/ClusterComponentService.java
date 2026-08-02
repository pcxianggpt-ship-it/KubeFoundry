package io.kubefoundry.cluster;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import io.kubefoundry.installer.InstallerAdmission;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClusterComponentService {
    private static final Set<String> NFS_FIELDS = Set.of(
            "server_address", "share_path", "worker_mount_path", "storage_class", "exports_mode");

    private final ClusterRepository clusters;
    private final ClusterComponentRepository components;
    private final ClusterComponentStateRepository states;
    private final InstallerAdmission admission;
    private final ObjectMapper mapper;

    public ClusterComponentService(
            ClusterRepository clusters,
            ClusterComponentRepository components,
            ClusterComponentStateRepository states,
            InstallerAdmission admission,
            ObjectMapper mapper) {
        this.clusters = clusters;
        this.components = components;
        this.states = states;
        this.admission = admission;
        this.mapper = mapper;
    }

    @Transactional(readOnly = true)
    public ComponentsResponse list(long clusterId) {
        Cluster cluster = requireCluster(clusterId);
        Map<String, ClusterComponent> configured = components.findByClusterIdOrderByComponentKey(clusterId).stream()
                .collect(Collectors.toMap(ClusterComponent::getComponentKey, component -> component));
        Map<String, ClusterComponentState> actual = states.findByClusterIdOrderByComponentKey(clusterId).stream()
                .collect(Collectors.toMap(ClusterComponentState::getComponentKey, state -> state));
        List<GroupResponse> groups = KubemateComponentCatalog.GROUPS.stream().map(definition -> {
            ClusterComponent component = configured.get(definition.key());
            ClusterComponentState state = actual.get(definition.key());
            return new GroupResponse(definition.key(), definition.name(),
                    component != null && component.isEnabled(), definition.available(), definition.components(),
                    state == null ? ClusterComponentState.NOT_INSTALLED : state.getStatus(),
                    parseConfig(component == null ? "{}" : component.getConfigJson()));
        }).toList();
        return new ComponentsResponse(cluster.isKubemateEnabled(), groups);
    }

    @Transactional
    public ComponentsResponse replace(long clusterId, ComponentsRequest request) {
        Cluster cluster = requireCluster(clusterId);
        admission.requireConfigurationWritable(clusterId, cluster.isInstallationLocked());
        if (request == null) throw invalid("请求体不能为空");
        List<GroupRequest> requested = request.groups();
        Map<String, GroupRequest> values = new LinkedHashMap<>();
        if (requested == null) {
            components.findByClusterIdOrderByComponentKey(clusterId).forEach(component -> {
                GroupRequest group = new GroupRequest(component.getComponentKey(), component.isEnabled(), parseConfig(component.getConfigJson()));
                group.setValidatedConfig(component.getConfigJson());
                values.put(component.getComponentKey(), group);
            });
        }
        for (GroupRequest group : requested == null ? List.<GroupRequest>of() : requested) {
            if (group == null || group.key() == null || KubemateComponentCatalog.find(group.key()) == null) {
                throw new ComponentConfigurationException("COMPONENT_GROUP_UNKNOWN", "未知的 Kubemate 组件组");
            }
            if (values.putIfAbsent(group.key(), group) != null) {
                throw invalid("组件组不能重复: " + group.key());
            }
            KubemateComponentCatalog.Group definition = KubemateComponentCatalog.find(group.key());
            if (group.enabled() && !definition.available()) {
                throw new ComponentConfigurationException("COMPONENT_GROUP_UNAVAILABLE", "组件组暂不可用: " + group.key());
            }
            String config = validateConfig(definition, group.config(), group.enabled());
            ClusterComponentState state = states.findByClusterIdAndComponentKey(clusterId, group.key()).orElse(null);
            ClusterComponent old = components.findByClusterIdAndComponentKey(clusterId, group.key()).orElse(null);
            if (state != null && ClusterComponentState.INSTALLED.equals(state.getStatus())
                    && (old == null || old.isEnabled() != group.enabled()
                    || !parseConfig(old.getConfigJson()).equals(parseConfig(config)))) {
                throw new ComponentConfigurationException("CLUSTER_CONFIGURATION_LOCKED", "已安装组件组不可修改: " + group.key());
            }
            group.setValidatedConfig(config);
        }
        cluster.updateKubemateEnabled(request.enabled());
        components.deleteByClusterId(clusterId);
        for (KubemateComponentCatalog.Group definition : KubemateComponentCatalog.GROUPS) {
            GroupRequest group = values.get(definition.key());
            if (group == null) group = new GroupRequest(definition.key(), false, Map.of());
            components.save(new ClusterComponent(cluster, definition.key(), group.enabled(), group.validatedConfig()));
            if (!states.existsByClusterIdAndComponentKey(clusterId, definition.key())) {
                states.save(new ClusterComponentState(cluster, definition.key()));
            }
        }
        return list(clusterId);
    }

    private String validateConfig(KubemateComponentCatalog.Group definition, Map<String, Object> config, boolean enabled) {
        Map<String, Object> values = config == null ? Map.of() : new LinkedHashMap<>(config);
        if (!"nfs".equals(definition.key())) {
            if (!values.isEmpty()) throw invalid(definition.key() + " 组件组暂不接受配置字段");
            return writeConfig(values);
        }
        if (!values.keySet().stream().allMatch(NFS_FIELDS::contains)) {
            throw invalid("NFS 配置包含未知字段");
        }
        if (enabled || !values.isEmpty()) {
            for (String field : NFS_FIELDS) {
                if (!values.containsKey(field)) throw invalid("NFS " + field + " 必填");
                requireString(values, field);
            }
            String server = (String) values.get("server_address");
            if (!server.matches("(?:\\d{1,3}\\.){3}\\d{1,3}")
                    || java.util.Arrays.stream(server.split("\\."))
                    .mapToInt(Integer::parseInt).anyMatch(part -> part > 255)) {
                throw invalid("NFS server_address 必须是 IPv4 地址");
            }
            if (!isSafeAbsolutePath((String) values.get("share_path"))) throw invalid("NFS share_path 必须是安全绝对路径");
            if (!isSafeAbsolutePath((String) values.get("worker_mount_path"))) throw invalid("NFS worker_mount_path 必须是安全绝对路径");
            String storageClass = (String) values.get("storage_class");
            if (!storageClass.matches("[a-z0-9](?:[-a-z0-9]*[a-z0-9])?") || storageClass.length() > 63) {
                throw invalid("NFS storage_class 必须是 Kubernetes 资源名称");
            }
            String mode = (String) values.get("exports_mode");
            if (!mode.equals("managed") && !mode.equals("external")) throw invalid("NFS exports_mode 必须为 managed 或 external");
        }
        return writeConfig(values);
    }

    private static void requireString(Map<String, Object> values, String key) {
        if (!(values.get(key) instanceof String) || ((String) values.get(key)).isBlank()) throw invalid("NFS " + key + " 必须是非空字符串");
    }

    private static boolean isSafeAbsolutePath(String path) {
        return path.startsWith("/") && !path.contains("//") && !path.matches(".*(?:^|/)\\.\\.?(?:/|$).*");
    }

    private String writeConfig(Map<String, Object> config) {
        try { return mapper.writeValueAsString(config); }
        catch (JsonProcessingException exception) { throw invalid("组件配置格式无效"); }
    }

    private Map<String, Object> parseConfig(String config) {
        try { return mapper.readValue(config, Map.class); }
        catch (JsonProcessingException exception) { return Map.of(); }
    }

    private static IllegalArgumentException invalid(String message) {
        return new ComponentConfigurationException("COMPONENT_CONFIG_INVALID", message);
    }

    private Cluster requireCluster(long id) {
        return clusters.findById(id).orElseThrow(() -> ClusterService.ResourceNotFoundException.cluster(id));
    }

    @JsonIgnoreProperties(ignoreUnknown = false)
    public record ComponentsRequest(boolean enabled, List<GroupRequest> groups) { }
    @JsonIgnoreProperties(ignoreUnknown = false)
    public static final class GroupRequest {
        private final String key;
        private final boolean enabled;
        private final Map<String, Object> config;
        private String validatedConfig = "{}";
        public GroupRequest(String key, boolean enabled, Map<String, Object> config) { this.key = key; this.enabled = enabled; this.config = config; }
        public String key() { return key; }
        public boolean enabled() { return enabled; }
        public Map<String, Object> config() { return config; }
        public String validatedConfig() { return validatedConfig; }
        void setValidatedConfig(String value) { validatedConfig = value; }
    }
    public record ComponentsResponse(boolean enabled, List<GroupResponse> groups) { }
    public record GroupResponse(String key, String name, boolean enabled, boolean available,
            List<String> components, String status, Map<String, Object> config) { }

    public static class ComponentConfigurationException extends IllegalArgumentException {
        private final String code;
        public ComponentConfigurationException(String code, String message) { super(message); this.code = code; }
        public String code() { return code; }
    }
}
