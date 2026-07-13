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
        String verifyCommand) {

    public InstallStep {
        if (key == null || key.isBlank()) throw new IllegalArgumentException("步骤键不能为空");
        if (name == null || name.isBlank()) throw new IllegalArgumentException("步骤名称不能为空");
        if (!List.of("serial", "parallel").contains(mode)) {
            throw new IllegalArgumentException("步骤执行模式无效: " + mode);
        }
        if (maxWorkers < 1) throw new IllegalArgumentException("步骤并发数必须大于 0");
        resources = resources == null ? List.of() : List.copyOf(resources);
        arguments = arguments == null ? List.of() : List.copyOf(arguments);
        outputs = outputs == null ? List.of() : List.copyOf(outputs);
        verifyCommand = verifyCommand == null ? "" : verifyCommand;
    }

    public static InstallStep script(
            String key,
            String name,
            String phase,
            String targetScope,
            Path script,
            String mode,
            int maxWorkers,
            boolean failFast,
            List<Resource> resources,
            List<Argument> arguments,
            List<Output> outputs,
            String verifyCommand) {
        return new InstallStep(key, name, phase, targetScope, script, null, mode,
                maxWorkers, failFast, resources, arguments, outputs, verifyCommand);
    }

    public static InstallStep builtin(
            String key,
            String name,
            String phase,
            String targetScope,
            String builtin,
            String mode,
            int maxWorkers,
            boolean failFast,
            String verifyCommand) {
        return new InstallStep(key, name, phase, targetScope, null, builtin, mode,
                maxWorkers, failFast, List.of(), List.of(), List.of(), verifyCommand);
    }

    public record Resource(String pathKey, String artifactKey, String kind, String remotePath) {
        public Resource {
            if ((pathKey == null || pathKey.isBlank())
                    == (artifactKey == null || artifactKey.isBlank())) {
                throw new IllegalArgumentException("资源必须且只能指定 pathKey 或 artifactKey");
            }
            kind = kind == null || kind.isBlank() ? "file" : kind;
            if (remotePath == null || remotePath.isBlank()) {
                throw new IllegalArgumentException("资源远端路径不能为空");
            }
        }
    }

    public record Argument(String literal, String contextKey) {
        public Argument {
            if ((literal == null) == (contextKey == null)) {
                throw new IllegalArgumentException("参数必须且只能指定 literal 或 contextKey");
            }
        }
    }

    public record Output(String key, String remotePath) {
        public Output {
            if (key == null || key.isBlank()) throw new IllegalArgumentException("产物键不能为空");
            if (remotePath == null || remotePath.isBlank()) {
                throw new IllegalArgumentException("产物远端路径不能为空");
            }
        }
    }
}
