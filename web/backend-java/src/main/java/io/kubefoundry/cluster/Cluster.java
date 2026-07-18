package io.kubefoundry.cluster;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "clusters")
public class Cluster {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 128)
    private String name;

    @Column(nullable = false, length = 512)
    private String description = "";

    @Column(name = "kubernetes_version", length = 64)
    private String kubernetesVersion;

    @Column(name = "pod_subnet", nullable = false, length = 64)
    private String podSubnet = "";

    @Column(name = "service_subnet", nullable = false, length = 64)
    private String serviceSubnet = "";

    @Column(name = "registry_hostname", nullable = false, length = 128)
    private String registryHostname = "";

    @Column(name = "registry_ip", nullable = false, length = 64)
    private String registryIp = "";

    @Column(name = "registry_port", nullable = false)
    private int registryPort = 5000;

    @Column(nullable = false, length = 32)
    private String status = "draft";

    @Column(name = "installation_locked", nullable = false)
    private boolean installationLocked;

    @Column(name = "node_config_version", nullable = false)
    private long nodeConfigVersion;

    @Column(name = "node_test_status", nullable = false, length = 32)
    private String nodeTestStatus = "pending";

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    protected Cluster() {
    }

    public Cluster(String name) {
        this.name = name;
    }

    public Long getId() { return id; }
    public String getName() { return name; }
    public String getDescription() { return description; }
    public String getKubernetesVersion() { return kubernetesVersion; }
    public String getPodSubnet() { return podSubnet; }
    public String getServiceSubnet() { return serviceSubnet; }
    public String getRegistryHostname() { return registryHostname; }
    public String getRegistryIp() { return registryIp; }
    public int getRegistryPort() { return registryPort; }
    public String getStatus() { return status; }
    public boolean isInstallationLocked() { return installationLocked; }
    public long getNodeConfigVersion() { return nodeConfigVersion; }
    public String getNodeTestStatus() { return nodeTestStatus; }

    public void update(
            String name,
            String description,
            String kubernetesVersion,
            String podSubnet,
            String serviceSubnet,
            String registryHostname,
            String registryIp,
            Integer registryPort,
            String status) {
        if (name != null) this.name = name;
        if (description != null) this.description = description;
        if (kubernetesVersion != null) this.kubernetesVersion = kubernetesVersion;
        if (podSubnet != null) this.podSubnet = podSubnet;
        if (serviceSubnet != null) this.serviceSubnet = serviceSubnet;
        if (registryHostname != null) this.registryHostname = registryHostname;
        if (registryIp != null) this.registryIp = registryIp;
        if (registryPort != null) this.registryPort = registryPort;
        if (status != null) this.status = status;
    }

    public void markNodeConfigurationChanged() {
        nodeConfigVersion++;
        nodeTestStatus = "stale";
    }

    public void markNodeTestStatus(String value) {
        nodeTestStatus = value;
    }

    public void markInstallationStarted() {
        status = "installing";
        installationLocked = true;
    }

    public void markInstallationFinished(boolean success) {
        status = success ? "installed" : "install_failed";
    }

    public void resetInstallation() {
        status = "draft";
        installationLocked = false;
        nodeTestStatus = "stale";
        nodeConfigVersion++;
    }
}
