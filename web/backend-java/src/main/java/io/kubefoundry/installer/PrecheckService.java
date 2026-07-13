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

    @Autowired
    public PrecheckService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            RemoteStepRunner runner,
            PrecheckResultRepository results,
            EventService events,
            InstallerAdmission admission) {
        this.clusters = clusters;
        this.nodes = nodes;
        this.jobs = jobs;
        this.jobService = jobService;
        this.runner = runner;
        this.results = results;
        this.events = events;
        this.admission = admission;
    }

    public PrecheckService(
            ClusterRepository clusters,
            NodeRepository nodes,
            JobRepository jobs,
            JobService jobService,
            RemoteStepRunner runner) {
        this(clusters, nodes, jobs, jobService, runner, null, null, new InstallerAdmission(jobs));
    }

    public long start(long clusterId) {
        Cluster cluster = clusters.findById(clusterId)
                .orElseThrow(() -> ResourceNotFoundException.cluster(clusterId));
        List<Node> configuredNodes = nodes.findByClusterIdOrderById(clusterId);
        InstallationGate.requireSuccessfulNodeTests(cluster, configuredNodes);
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
        List<PrecheckCheck> checks = buildChecks(node, values, os);
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

    private static List<PrecheckCheck> buildChecks(
            Node node, Map<String, String> values, OsInfo os) {
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
        return checks;
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
