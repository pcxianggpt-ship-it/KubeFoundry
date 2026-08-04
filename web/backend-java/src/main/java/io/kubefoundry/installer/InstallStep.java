package io.kubefoundry.installer;

import java.nio.file.Path;
import java.util.List;

public record InstallStep(
        String key,
        String name,
        String phase,
        String targetScope,
        Path script,
        String builtin,
        String mode,
        int maxWorkers,
        boolean failFast,
        List<Resource> resources,
        List<Argument> arguments,
        List<Output> outputs,
        String verifyCommand,
        String componentGroupKey) {

    public InstallStep {
        if (key == null || key.isBlank()) throw new IllegalArgumentException("Step key is required");
        if (name == null || name.isBlank()) throw new IllegalArgumentException("Step name is required");
        if (!List.of("serial", "parallel").contains(mode)) {
            throw new IllegalArgumentException("Invalid step execution mode: " + mode);
        }
        if (maxWorkers < 1) throw new IllegalArgumentException("Step worker limit must be positive");
        resources = resources == null ? List.of() : List.copyOf(resources);
        arguments = arguments == null ? List.of() : List.copyOf(arguments);
        outputs = outputs == null ? List.of() : List.copyOf(outputs);
        verifyCommand = verifyCommand == null ? "" : verifyCommand;
        componentGroupKey = componentGroupKey == null || componentGroupKey.isBlank()
                ? null : componentGroupKey.trim();
    }

    public static InstallStep script(
            String key, String name, String phase, String targetScope, Path script, String mode,
            int maxWorkers, boolean failFast, List<Resource> resources, List<Argument> arguments,
            List<Output> outputs, String verifyCommand) {
        return new InstallStep(key, name, phase, targetScope, script, null, mode,
                maxWorkers, failFast, resources, arguments, outputs, verifyCommand, null);
    }

    public static InstallStep builtin(
            String key, String name, String phase, String targetScope, String builtin, String mode,
            int maxWorkers, boolean failFast, String verifyCommand) {
        return new InstallStep(key, name, phase, targetScope, null, builtin, mode,
                maxWorkers, failFast, List.of(), List.of(), List.of(), verifyCommand, null);
    }

    public static InstallStep componentScript(
            String key, String name, String targetScope, Path script, String componentGroupKey,
            String mode, int maxWorkers, boolean failFast, String verifyCommand) {
        return new InstallStep(key, name, "kubemate_component", targetScope, script, null, mode,
                maxWorkers, failFast, List.of(), List.of(), List.of(), verifyCommand, componentGroupKey);
    }

    public InstallStep withResources(List<Resource> updatedResources) {
        return new InstallStep(key, name, phase, targetScope, script, builtin, mode, maxWorkers,
                failFast, updatedResources, arguments, outputs, verifyCommand, componentGroupKey);
    }

    public record Resource(
            String pathKey,
            String artifactKey,
            String kind,
            String remotePath,
            Path localPath,
            String checksum) {
        public Resource(String pathKey, String artifactKey, String kind, String remotePath) {
            this(pathKey, artifactKey, kind, remotePath, null, null);
        }

        public Resource {
            int sources = (pathKey == null || pathKey.isBlank() ? 0 : 1)
                    + (artifactKey == null || artifactKey.isBlank() ? 0 : 1)
                    + (localPath == null ? 0 : 1);
            if (sources != 1) {
                throw new IllegalArgumentException("A resource requires exactly one source");
            }
            kind = kind == null || kind.isBlank() ? "file" : kind;
            if (remotePath == null || remotePath.isBlank()) {
                throw new IllegalArgumentException("Resource remote path is required");
            }
            localPath = localPath == null ? null : localPath.toAbsolutePath().normalize();
            checksum = checksum == null || checksum.isBlank() ? null : checksum.toLowerCase(java.util.Locale.ROOT);
            if (checksum != null && !checksum.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("Resource checksum must be SHA-256");
            }
        }

        public static Resource local(Path localPath, String kind, String remotePath) {
            return new Resource(null, null, kind, remotePath, localPath, null);
        }

        public Resource withChecksum(String value) {
            return new Resource(pathKey, artifactKey, kind, remotePath, localPath, value);
        }
    }

    public record Argument(String literal, String contextKey) {
        public Argument {
            if ((literal == null) == (contextKey == null)) {
                throw new IllegalArgumentException("An argument requires exactly one value source");
            }
        }
    }

    public record Output(String key, String remotePath) {
        public Output {
            if (key == null || key.isBlank()) throw new IllegalArgumentException("Output key is required");
            if (remotePath == null || remotePath.isBlank()) {
                throw new IllegalArgumentException("Output remote path is required");
            }
        }
    }
}
