package io.kubefoundry.installer;

import java.nio.file.Path;
import java.util.List;
import java.util.Map;

public record RuntimeSettings(
        Map<String, String> paths,
        Map<String, String> env,
        Map<String, Object> advanced) {

    public RuntimeSettings {
        paths = paths == null ? Map.of() : Map.copyOf(paths);
        env = env == null ? Map.of() : Map.copyOf(env);
        advanced = advanced == null ? Map.of() : Map.copyOf(advanced);
    }

    public String path(String key) {
        return paths.getOrDefault(key, "");
    }

    public Path localPath(String key) {
        String value = path(key);
        return value.isBlank() ? null : Path.of(value);
    }

    public String k8sHome() {
        return path("k8s_home");
    }

    public String installMedia() {
        return path("install_media");
    }

    public String kubeletRoot() {
        return env.getOrDefault("kubelet_root", "");
    }

    public String containerdRoot() {
        return env.getOrDefault("containerd_root", "");
    }

    public String etcdDataDir() {
        return env.getOrDefault("etcd_data_dir", "");
    }

    public boolean dualStackEnabled() {
        Object value = advanced.get("enable_ipv6_dual_stack");
        if (value instanceof Boolean bool) return bool;
        return value != null && List.of("true", "y", "yes", "1")
                .contains(value.toString().trim().toLowerCase());
    }
}
