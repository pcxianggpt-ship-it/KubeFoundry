package io.kubefoundry.installer;

import io.kubefoundry.cluster.Cluster;
import io.kubefoundry.cluster.ClusterRepository;
import io.kubefoundry.cluster.ClusterService.ResourceNotFoundException;
import io.kubefoundry.cluster.Node;
import io.kubefoundry.cluster.NodeRepository;
import io.kubefoundry.job.EventService;
import io.kubefoundry.job.Job;
import io.kubefoundry.job.JobRepository;
import io.kubefoundry.job.JobService;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class PrecheckService {

    static final String CHECK_COMMAND = """
            set -o pipefail
            echo "__KF__USER=$(id -u 2>/dev/null || echo -1)"
            echo "__KF__OS=$(cat /etc/os-release 2>/dev/null | head -n 1 || uname -a)"
            echo "__KF__CPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0)"
            echo "__KF__MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
            echo "__KF__DISK=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
            echo "__KF__SWAP=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
            echo "__KF__HOSTNAME=$(hostname 2>/dev/null || echo unknown)"
            echo "__KF__ARCH=$(uname -m 2>/dev/null || echo unknown)"
            command -v bash >/dev/null 2>&1 && echo "__KF__BASH=present" || echo "__KF__BASH=missing"
            command -v systemctl >/dev/null 2>&1 && echo "__KF__SYSTEMD=present" || echo "__KF__SYSTEMD=missing"
            cat /etc/os-release 2>/dev/null | sed 's/^/__KF__OS_RELEASE__/'
            for p in 6443 2379 2380 10250 10257 10259; do
              if command -v ss >/dev/null 2>&1; then
                ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && echo "__KF__PORT_${p}=used" || echo "__KF__PORT_${p}=free"
              else
                netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && echo "__KF__PORT_${p}=used" || echo "__KF__PORT_${p}=free"
              fi
            done
            """;

    private final ClusterRepository clusters;
    private final NodeRepository nodes;
    private final JobRepository jobs;
    private final JobService jobService;
    private final RemoteStepRunner runner;
    private final PrecheckResultRepository results;
    private final EventService events;
    private final InstallerAdmission admission;
    private final ClusterSettingsService settings;
    private final InstallationReadinessValidator readiness;

    @Autowired
    public PrecheckService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            RemoteStepRunner runner,
            PrecheckResultRepository results,
            EventService events,
            InstallerAdmission admission,
            ClusterSettingsService settings,
            InstallationReadinessValidator readiness) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.jobService = jobService;
        this.runner = runner;
        this.results = results;
        this.events = events;
        this.admission = admission;
        this.settings = settings;
        this.readiness = readiness;
    }

    PrecheckService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            RemoteStepRunner runner,
            PrecheckResultRepository results,
            EventService events,
            InstallerAdmission admission,
            ClusterSettingsService settings) {
        this(clusters, nodes, jobs, jobService, runner, results, events, admission, settings, null);
    }

    public long start(long clusterId) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
        List<Node> configuredNodes = InstallationNodes.normalize(
                nodes.findByClusterIdOrderById(clusterId));
        if (readiness != null) {
            readiness.validate(cluster, configuredNodes);
        } else {
            if (configuredNodes.stream().anyMatch(node -> !node.getRoles().isEmpty())) {
                ClusterTopologyValidator.requireValid(configuredNodes, cluster.getImageRegistryType());
            }
            InstallationGate.requireSuccessfulNodeTests(cluster, configuredNodes);
        }
        List<JobService.NodeOperation> operations = configuredNodes.stream()
                .map(node -> JobService.NodeOperation.withOutcome(node.getId(), jobId ->
                        runPrecheck(jobId, cluster, node)))
                .toList();
        JobService.StepDefinition step = new JobService.StepDefinition(
                "节点环境预检查", 1, 5, false, operations);
        return admission.submit(clusterId, () -> jobService.submit(new JobService.JobDefinition(
                clusterId, "precheck", List.of(step))));
    }

    private JobService.NodeOutcome runPrecheck(long jobId, Cluster cluster, Node node) {
        RemoteStepRunner.CommandOutcome command = runner.runCommandCapture(
                jobId, cluster, node, "web-precheck-node-env", CHECK_COMMAND, Duration.ofSeconds(60));
        Job job = jobs.findById(jobId).orElseThrow();
        if (command.exitCode() != 0) {
            PrecheckCheck ssh = new PrecheckCheck("ssh", "SSH 连通性", "error", "fail",
                    "SSH 连接失败", command.stderr().isBlank() ? command.stdout() : command.stderr());
            persist(jobId, cluster, job, node, ssh);
            return new JobService.NodeOutcome(false, command.exitCode(),
                    "预检查失败: SSH 连接失败", command.logPath());
        }

        Map<String, String> values = parseMarkers(command.stdout());
        OsInfo os = parseOsRelease(command.stdout(), values.get("OS"));
        List<PrecheckCheck> checks = buildChecks(cluster, node, values, os);
        if (checks.stream().anyMatch(check -> "system_drift".equals(check.key())
                && "fail".equals(check.status()))) {
            node.markTestStale(false);
            nodes.saveAndFlush(node);
            clusters.markNodeConfigurationChanged(cluster.getId());
        }
        boolean failed = false;
        for (PrecheckCheck check : checks) {
            persist(jobId, cluster, job, node, check);
            if ("error".equals(check.severity()) && "fail".equals(check.status())) {
                failed = true;
            }
        }
        return new JobService.NodeOutcome(!failed, failed ? 1 : 0,
                failed ? "预检查存在 error 级失败" : "预检查通过", command.logPath());
    }

    private void persist(long jobId, Cluster cluster, Job job, Node node, PrecheckCheck check) {
        if (results != null) {
            results.saveAndFlush(new PrecheckResult(cluster, job, node, check.key(), check.name(),
                    check.severity(), check.status(), check.message(), check.detail()));
        }
        if (events != null) {
            events.publish(jobId, "precheck.result", Map.of(
                    "node_id", node.getId(),
                    "hostname", node.getHostname(),
                    "check_key", check.key(),
                    "status", check.status(),
                    "severity", check.severity(),
                    "message", check.message()));
        }
    }

    private List<PrecheckCheck> buildChecks(
            Cluster cluster, Node node, Map<String, String> values, OsInfo os) {
        List<PrecheckCheck> checks = new ArrayList<>();
        checks.add(new PrecheckCheck("ssh", "SSH 连通性", "error", "pass",
                "SSH 连接成功", ""));
        boolean root = "0".equals(values.get("USER"));
        checks.add(new PrecheckCheck("user", "用户权限", "warning",
                root ? "pass" : "warning", root ? "root 用户" : "非 root 用户",
                values.getOrDefault("USER", "")));
        checks.add(new PrecheckCheck("os", "操作系统版本", "info", "pass",
                (os.type() + " " + os.version()).trim(), values.getOrDefault("OS", "")));
        String arch = normalizeArch(values.get("ARCH"));
        checks.add(new PrecheckCheck("arch", "系统架构", "error",
                arch.isBlank() ? "fail" : "pass", arch.isBlank() ? "unknown" : arch, ""));
        PrecheckCheck drift = systemDrift(node, os, arch);
        if (drift != null) checks.add(drift);
        int cpu = integer(values.get("CPU"));
        checks.add(new PrecheckCheck("cpu", "CPU", "error",
                cpu >= 2 ? "pass" : "fail", "CPU 核数: " + cpu, "建议至少 2 核"));
        int memory = integer(values.get("MEM"));
        checks.add(new PrecheckCheck("memory", "内存", "error",
                memory >= 2048 ? "pass" : "fail", "内存: " + memory + " MB", "建议至少 2048 MB"));
        int disk = integer(values.get("DISK"));
        checks.add(new PrecheckCheck("disk", "磁盘", "warning",
                disk >= 10240 ? "pass" : "warning", "根分区可用: " + disk + " MB", "建议至少 10240 MB"));
        int swap = integer(values.get("SWAP"));
        checks.add(new PrecheckCheck("swap", "Swap", "warning",
                swap == 0 ? "pass" : "warning", "Swap: " + swap + " MB", "Kubernetes 建议关闭 swap"));
        checks.add(new PrecheckCheck("bash", "bash", "error",
                "present".equals(values.get("BASH")) ? "pass" : "fail",
                "present".equals(values.get("BASH")) ? "bash 可用" : "bash 缺失", ""));
        checks.add(new PrecheckCheck("systemd", "systemd", "error",
                "present".equals(values.get("SYSTEMD")) ? "pass" : "fail",
                "present".equals(values.get("SYSTEMD")) ? "systemd 可用" : "systemd 缺失", ""));
        checks.add(new PrecheckCheck("hostname", "Hostname", "info", "pass",
                values.getOrDefault("HOSTNAME", "unknown"), ""));
        List<String> usedPorts = List.of("6443", "2379", "2380", "10250", "10257", "10259")
                .stream().filter(port -> "used".equals(values.get("PORT_" + port))).toList();
        checks.add(new PrecheckCheck("ports", "关键端口", "error",
                usedPorts.isEmpty() ? "pass" : "fail",
                usedPorts.isEmpty() ? "关键端口未占用" : "端口占用: " + String.join(",", usedPorts),
                ""));
        checks.add(controlPlaneCount(cluster));
        checks.add(offlineMediaDirectory(cluster, node));
        return checks;
    }

    private PrecheckCheck controlPlaneCount(Cluster cluster) {
        int count = InstallationNodes.normalize(nodes.findByClusterIdOrderById(cluster.getId())).stream()
                .filter(node -> node.hasRole("control_plane")
                        || "control_plane".equals(node.getRole()))
                .toList().size();
        boolean valid = count == 1 || count == 3;
        return new PrecheckCheck("control_plane_count", "\u63A7\u5236\u8282\u70B9\u6570\u91CF", "error",
                valid ? "pass" : "fail",
                valid ? "\u63A7\u5236\u8282\u70B9\u6570\u91CF: " + count + "\uFF0C\u7B26\u5408\u8981\u6C42"
                        : "\u63A7\u5236\u8282\u70B9\u6570\u91CF: " + count
                                + "\uFF0C\u4EC5\u652F\u6301 1 \u6216 3 \u4E2A\u63A7\u5236\u8282\u70B9",
                "\u96C6\u7FA4\u53EA\u652F\u6301\u5355\u63A7\u5236\u8282\u70B9\u6216"
                        + "\u4E09\u63A7\u5236\u8282\u70B9\u9AD8\u53EF\u7528\u90E8\u7F72");
    }

    private PrecheckCheck offlineMediaDirectory(Cluster cluster, Node node) {
        String directory = settings.runtimeSettings(cluster, node).installMedia();
        boolean exists = false;
        try {
            exists = !directory.isBlank() && Files.isDirectory(Path.of(directory));
        } catch (InvalidPathException ignored) {
            // Invalid paths are reported as a failed precheck result below.
        }
        return new PrecheckCheck("offline_media", "\u79BB\u7EBF\u4ECB\u8D28\u76EE\u5F55", "error",
                exists ? "pass" : "fail",
                exists ? "\u79BB\u7EBF\u4ECB\u8D28\u76EE\u5F55\u5B58\u5728: " + directory
                        : "\u79BB\u7EBF\u4ECB\u8D28\u76EE\u5F55\u4E0D\u5B58\u5728: " + directory,
                "\u8BF7\u5728\u7BA1\u7406\u8282\u70B9\u4E0A\u914D\u7F6E\u5E76\u51C6\u5907"
                        + "\u6709\u6548\u7684\u79BB\u7EBF\u5B89\u88C5\u4ECB\u8D28\u76EE\u5F55");
    }

    private static PrecheckCheck systemDrift(Node node, OsInfo os, String arch) {
        List<String> details = new ArrayList<>();
        if (hasText(node.getOsType()) && hasText(os.type())
                && !node.getOsType().equals(os.type())) {
            details.add("发行版 " + node.getOsType() + " -> " + os.type());
        }
        if (hasText(node.getOsVersion()) && hasText(os.version())
                && !major(node.getOsVersion()).equals(major(os.version()))) {
            details.add("主版本 " + node.getOsVersion() + " -> " + os.version());
        }
        if (hasText(node.getArchitecture()) && hasText(arch)
                && !node.getArchitecture().equals(arch)) {
            details.add("架构 " + node.getArchitecture() + " -> " + arch);
        }
        if (details.isEmpty()) return null;
        return new PrecheckCheck("system_drift", "系统信息变化", "error", "fail",
                "节点系统信息与最近一次节点测试不一致", String.join("；", details));
    }

    private static Map<String, String> parseMarkers(String output) {
        Map<String, String> values = new LinkedHashMap<>();
        for (String line : (output == null ? "" : output).split("\\R")) {
            if (!line.startsWith("__KF__") || !line.contains("=")) continue;
            int separator = line.indexOf('=');
            values.put(line.substring(6, separator), line.substring(separator + 1).trim());
        }
        return values;
    }

    private static OsInfo parseOsRelease(String output, String fallback) {
        Map<String, String> fields = new LinkedHashMap<>();
        for (String line : (output == null ? "" : output).split("\\R")) {
            if (!line.startsWith("__KF__OS_RELEASE__") || !line.contains("=")) continue;
            String item = line.substring("__KF__OS_RELEASE__".length());
            int separator = item.indexOf('=');
            fields.put(item.substring(0, separator), stripQuotes(item.substring(separator + 1)));
        }
        String type = value(fields.get("ID"), "");
        String version = value(fields.get("VERSION_ID"), "");
        if (type.isBlank() && fallback != null) type = fallback.split("\\s+", 2)[0].toLowerCase(Locale.ROOT);
        return new OsInfo(type, version);
    }

    private static String normalizeArch(String value) {
        String arch = value(value, "").toLowerCase(Locale.ROOT);
        return switch (arch) {
            case "x86_64", "amd64" -> "amd64";
            case "aarch64", "arm64" -> "arm64";
            default -> arch;
        };
    }

    private static String stripQuotes(String value) {
        String text = value(value, "").trim();
        return text.length() >= 2 && text.startsWith("\"") && text.endsWith("\"")
                ? text.substring(1, text.length() - 1)
                : text;
    }

    private static String major(String value) {
        String text = value(value, "");
        int dot = text.indexOf('.');
        return dot >= 0 ? text.substring(0, dot) : text;
    }

    private static int integer(String value) {
        try {
            return Integer.parseInt(value(value, "0"));
        } catch (NumberFormatException exception) {
            return 0;
        }
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private static String value(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private record OsInfo(String type, String version) {
    }

    private record PrecheckCheck(
            String key,
            String name,
            String severity,
            String status,
            String message,
            String detail) {
    }
}
