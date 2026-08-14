package io.kubefoundry.installer;

import io.kubefoundry.cluster.KubemateComponentCatalog;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Resolves only KubeFoundry-owned offline media into immutable plan resources. */
@Component
public class ComponentMediaService {
    private static final String JOB_RESOURCE_ROOT = "/tmp/kubefoundry/jobs/{job_id}/resources";

    private final Path projectRoot;

    public ComponentMediaService(Path projectRoot) {
        this.projectRoot = projectRoot.toAbsolutePath().normalize();
    }

    @Autowired
    public ComponentMediaService(@Value("${kubefoundry.project-dir:}") String configuredProjectRoot) {
        this(configuredProjectRoot == null || configuredProjectRoot.isBlank()
                ? BaseInstallPlanFactory.discoverProjectRoot(Path.of("").toAbsolutePath())
                : Path.of(configuredProjectRoot));
    }

    Path projectRoot() {
        return projectRoot;
    }

    public InstallStep.Resource helmResource(InstallationSnapshotPayload snapshot) {
        String file = switch (primaryArchitecture(snapshot)) {
            case "amd64" -> "helm-amd";
            case "arm64" -> "helm-arm";
            default -> throw new IllegalArgumentException("Unsupported primary control-plane architecture");
        };
        return InstallStep.Resource.local(projectRoot.resolve("tools").resolve(file), "file",
                JOB_RESOURCE_ROOT + "/shared/helm");
    }

    public InstallStep.Resource componentResource(
            InstallationSnapshotPayload snapshot, String groupKey, String stepKey) {
        if (KubemateComponentCatalog.find(groupKey) == null) {
            throw new IllegalArgumentException("Unknown component media group: " + groupKey);
        }
        String version = snapshot.kubernetesVersion();
        if (version == null || version.isBlank()) version = "unknown";
        if (!version.matches("[0-9A-Za-z._-]+")) {
            throw new IllegalArgumentException("Invalid Kubernetes media version");
        }
        MediaLocation location = switch (stepKey) {
            case "31-install-kubemate-ui" -> new MediaLocation("directory", "kubemate");
            case "32-install-nfs" -> new MediaLocation("directory", "helmapp/nfs/nfs-subdir-external-provisioner");
            case "36-install-traefik" -> new MediaLocation("directory", "traefik/3.3");
            case "47-install-openebs" -> new MediaLocation("directory", "helmapp/openebs");
            case "49-install-minio" -> new MediaLocation("directory", "minio");
            case "35-install-loki" -> new MediaLocation("directory", "helmapp/loki");
            case "48-install-alloy" -> new MediaLocation("directory", "helmapp/alloy");
            case "38-install-prometheus" -> new MediaLocation("directory", "prometheus");
            default -> throw new IllegalArgumentException("No offline media mapping for step: " + stepKey);
        };
        Path source = projectRoot.resolve("kube-media").resolve("03.setup_file")
                .resolve("v" + version).resolve(location.relativePath()).normalize();
        requireWithinProject(source);
        String remotePath = JOB_RESOURCE_ROOT + "/" + groupKey
                + ("directory".equals(location.kind()) ? "" : "/" + stepKey);
        return InstallStep.Resource.local(source, location.kind(), remotePath);
    }

    public InstallPlan verifyAndChecksum(InstallPlan plan) {
        List<InstallStep> steps = plan.steps().stream().map(step -> step.withResources(step.resources().stream()
                .map(this::verifyAndChecksum).toList())).toList();
        return new InstallPlan(steps);
    }

    public Map<String, String> checksums(InstallPlan plan) {
        Map<String, String> checksums = new LinkedHashMap<>();
        for (InstallStep step : plan.steps()) {
            for (InstallStep.Resource resource : step.resources()) {
                if (resource.localPath() != null && resource.checksum() != null) {
                    checksums.put(relativeKey(resource.localPath()), resource.checksum());
                }
            }
        }
        return Map.copyOf(checksums);
    }

    private InstallStep.Resource verifyAndChecksum(InstallStep.Resource resource) {
        if (resource.localPath() == null) return resource;
        Path source = resource.localPath();
        requireWithinProject(source);
        if (!Files.exists(source, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalArgumentException("Component media is missing: " + source);
        }
        if (Files.isSymbolicLink(source)) {
            throw new IllegalArgumentException("Component media cannot be a symbolic link: " + source);
        }
        boolean expectedDirectory = "directory".equals(resource.kind());
        if (expectedDirectory != Files.isDirectory(source, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalArgumentException("Component media type does not match its plan: " + source);
        }
        if (!expectedDirectory && !Files.isRegularFile(source, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalArgumentException("Component media must be a regular file: " + source);
        }
        return resource.withChecksum(sha256(source));
    }

    private String primaryArchitecture(InstallationSnapshotPayload snapshot) {
        String architecture = snapshot.nodes().stream()
                .filter(node -> node.roles().contains("control_plane"))
                .min(Comparator.comparingLong(InstallationSnapshotPayload.NodeTarget::id))
                .map(InstallationSnapshotPayload.NodeTarget::architecture)
                .orElseThrow(() -> new IllegalArgumentException("Component installation requires a control plane"));
        return switch (architecture.toLowerCase(Locale.ROOT)) {
            case "amd64", "x86_64" -> "amd64";
            case "arm64", "aarch64" -> "arm64";
            default -> throw new IllegalArgumentException("Unsupported primary control-plane architecture: "
                    + architecture);
        };
    }

    private String sha256(Path source) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            if (Files.isDirectory(source, LinkOption.NOFOLLOW_LINKS)) {
                try (var paths = Files.walk(source)) {
                    for (Path path : paths.sorted().toList()) {
                        if (Files.isSymbolicLink(path)) {
                            throw new IllegalArgumentException("Component media cannot contain symbolic links: " + path);
                        }
                        if (Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) continue;
                        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                            throw new IllegalArgumentException("Component media contains an invalid file: " + path);
                        }
                        digest.update(source.relativize(path).toString().replace('\\', '/').getBytes(
                                StandardCharsets.UTF_8));
                        digest.update((byte) 0);
                        updateDigest(digest, path);
                    }
                }
            } else {
                updateDigest(digest, source);
            }
            return java.util.HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException | IOException exception) {
            throw new IllegalStateException("Unable to calculate component media SHA-256: " + source, exception);
        }
    }

    private static void updateDigest(MessageDigest digest, Path source) throws IOException {
        try (InputStream input = Files.newInputStream(source)) {
            byte[] buffer = new byte[8192];
            for (int read; (read = input.read(buffer)) >= 0; ) digest.update(buffer, 0, read);
        }
    }

    private void requireWithinProject(Path path) {
        if (!path.toAbsolutePath().normalize().startsWith(projectRoot)) {
            throw new IllegalArgumentException("Component media path escapes the project directory: " + path);
        }
    }

    private String relativeKey(Path path) {
        requireWithinProject(path);
        return projectRoot.relativize(path).toString().replace('\\', '/');
    }

    private record MediaLocation(String kind, String relativePath) {
    }
}
