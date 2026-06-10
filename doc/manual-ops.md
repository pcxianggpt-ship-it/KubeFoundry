# KubeFoundry 手动操作手册

> 基于 `config/cluster.yaml` 配置自动生成，按脚本执行顺序编排。
>
> **节点规划（3 控制节点 + 6 工作节点）：**
>
> | 角色       | 主机名    | IP              | 说明                          |
> | ---------- | --------- | --------------- | ----------------------------- |
> | 主控制节点 | k8sc1     | 192.168.123.130 | 镜像仓库节点                  |
> | 从控制节点 | k8sc2     | 192.168.123.131  |                               |
> | 从控制节点 | k8sc3     | 192.168.123.132  |                               |
> | 工作节点   | k8sw1     | 192.168.123.21 | NFS 服务器                    |
> | 工作节点   | k8sw2     | 192.168.123.22 |                               |
> | 工作节点   | k8sw3     | 192.168.123.23  |                               |
> | 工作节点   | k8sw4     | 192.168.123.24  |                               |
> | 工作节点   | k8sw5     | 192.168.123.25  |                               |
> | 工作节点   | k8sw6     | 192.168.123.26  |                               |
>
> **术语约定：**
>
> - **所有节点** = k8sc1 + k8sc2 + k8sc3 + k8sw1 ~ k8sw6（共 9 台）
> - **所有控制节点** = k8sc1 + k8sc2 + k8sc3
> - **所有工作节点** = k8sw1 ~ k8sw6
> - **除主控外所有节点** = k8sc2 + k8sc3 + k8sw1 ~ k8sw6
> - 以下操作若无特殊说明，均在 **主控制节点 k8sc1** 上以 root 身份执行。
> - 每个步骤标题已标明执行机器，需分别登录对应节点执行。

---

## 阶段一：K8S 基础环境安装

### 1.1 配置本地 yum 源

**登录 k8sc1 执行：**

```bash
# 解压安装包到 httpd 目录
mkdir -p /var/www/html/
tar -zxf /root/kube-media/01.rpm_package/k8srepo_kylinos_amd64.tar.gz -C /var/www/html/

# 创建 yum 源配置
cat > /etc/yum.repos.d/k8s.repo << 'EOF'
[k8s-yum]
name=rhel7
baseurl=file:///var/www/html/repo/
enabled=1
gpgcheck=0
EOF

# 刷新缓存
yum clean all
yum makecache

# 验证 yum 源可用
yum search kubelet | head -5

# 安装 httpd 并启动（供其他节点通过 HTTP 访问 yum 源）
yum install -y httpd sshpass
systemctl enable httpd --now

# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld
```

**验证：**
```bash
systemctl is-active httpd
curl -s http://k8sc1/repo/ | head -5
```

---

### 1.2 配置主机名和 hosts 解析

#### 1.2.1 设置主机名

**登录所有节点执行对应的命令（按实际主机名替换）：**

```bash
hostnamectl set-hostname <主机名>
# k8sc1: hostnamectl set-hostname k8sc1
# k8sc2: hostnamectl set-hostname k8sc2
# k8sc3: hostnamectl set-hostname k8sc3
# k8sw1: hostnamectl set-hostname k8sw1
# k8sw2: hostnamectl set-hostname k8sw2
# k8sw3: hostnamectl set-hostname k8sw3
# k8sw4: hostnamectl set-hostname k8sw4
# k8sw5: hostnamectl set-hostname k8sw5
# k8sw6: hostnamectl set-hostname k8sw6
```

#### 1.2.2 配置 /etc/hosts

**登录所有节点执行：**

```bash
cp /etc/hosts /etc/hosts.bak

# 删除旧的 KubeFoundry 标记段（重复执行时）
sed -i '/^# >>>KubeFoundry>>>/,/^# <<<KubeFoundry<</d' /etc/hosts

# 追加集群解析条目
cat >> /etc/hosts << 'EOF'
# >>>KubeFoundry>>>
192.168.123.130    k8sc1    registry
192.168.123.131     k8sc2
192.168.123.132     k8sc3
192.168.123.21    k8sw1
192.168.123.22    k8sw2
192.168.123.23     k8sw3
192.168.123.24     k8sw4
192.168.123.25     k8sw5
192.168.123.26     k8sw6
# <<<KubeFoundry<<<
EOF
```

**验证（所有节点）：**
```bash
hostname
grep -A10 'KubeFoundry' /etc/hosts
ping -c 1 k8sc1 && ping -c 1 k8sw1
```

---

### 1.3 配置 k8s repo 源客户端

**登录除 k8sc1 外所有节点执行：**

> k8sc1 已在步骤 1.1 配置了本地 yum 源，其余节点通过 HTTP 访问。

```bash
cat > /etc/yum.repos.d/k8s-http.repo << 'EOF'
[k8s-repo]
name=http
baseurl=http://k8sc1/repo
enabled=1
gpgcheck=0
EOF

yum clean all
yum makecache
```

**验证：**
```bash
yum search kubelet | head -3
```

---

### 1.4 安装 K8s 依赖包

**登录所有节点执行：**

```bash
yum install -y cri-tools kubeadm kubectl kubelet kubernetes-cni nfs-utils
systemctl enable kubelet
```

**验证（所有节点）：**
```bash
rpm -q cri-tools kubeadm kubectl kubelet kubernetes-cni nfs-utils
systemctl is-enabled kubelet
```

---

### 1.5 替换 kubeadm 为 100 年证书版本

**登录 k8sc1 执行：**

```bash
# 备份原始 kubeadm
mkdir -p /tmp/k8s
cp /usr/bin/kubeadm /tmp/k8s/kubeadm_bak

# 替换为 100 年证书版本
cp /root/kube-media/01.rpm_package/kubeadm-v1.30.14-100y-amd64 /usr/bin/kubeadm
chmod +x /usr/bin/kubeadm
```

**验证：**
```bash
kubeadm version
```

---

### 1.6 环境配置

**登录所有节点执行：**

```bash
# 关闭 swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld

# 卸载 podman 等冲突容器
yum remove -y podman containerd

# 配置 DNS
sed -i '/nameserver/d' /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# 加载内核模块
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 配置内核参数
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-iptables/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-ip6tables/d' /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-ip6tables=1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# 配置 IPv6
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.forwarding/d' /etc/sysctl.conf
echo "net.ipv6.conf.all.disable_ipv6=0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=0" >> /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6=0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf

# 应用内核参数
sysctl --system

# 启用 systemd-resolved
systemctl enable systemd-resolved

# 修改 open files 限制
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
```

**验证（所有节点）：**
```bash
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
free -h | grep -i swap   # 应无输出
```

---

### 1.7 安装 containerd

#### 1.7.1 分发安装包

**登录 k8sc1 执行：**

```bash
mkdir -p /tmp/k8s
cp -r /root/kube-media/02.container_runtime /tmp/k8s/
```

**登录除 k8sc1 外所有节点执行：**

> 从 k8sc1 将安装包拷贝到本机：`scp -r k8sc1:/tmp/k8s/02.container_runtime /tmp/k8s/`

#### 1.7.2 安装

**登录所有节点执行：**

```bash
cd /tmp/k8s/02.container_runtime

# 安装 containerd
tar Cxzvf /usr/local containerd-1.7.18-linux-amd64.tar.gz
cp containerd.service /etc/systemd/system/containerd.service

# 安装 runc
install -m 755 runcv1.3.3.amd64 /usr/local/sbin/runc

# 安装 CNI 插件
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.8.0.tgz

# 生成 containerd 配置文件
mkdir -p /etc/containerd
cp config-1.7.18.toml /etc/containerd/config.toml

# 安装 buildkit
tar Cxzvf /usr/local buildkit-v0.25.2.linux-amd64.tar.gz
cp buildkit.s* /etc/systemd/system/
systemctl daemon-reload
systemctl enable buildkit.service --now

# 安装 nerdctl
tar -zxf nerdctl-2.2.0-linux-amd64.tar.gz
chmod +x nerdctl
mv nerdctl /usr/local/bin/

# 配置镜像仓库（IP 方式）
mkdir -p /etc/containerd/certs.d/192.168.123.130:5000
cat > /etc/containerd/certs.d/192.168.123.130:5000/hosts.toml << 'EOF'
server = "http://192.168.123.130:5000"

[host."http://192.168.123.130:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 配置镜像仓库（域名方式）
mkdir -p /etc/containerd/certs.d/registry:5000
cat > /etc/containerd/certs.d/registry:5000/hosts.toml << 'EOF'
server = "http://registry:5000"

[host."http://registry:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 启动 containerd
systemctl daemon-reload
systemctl enable --now containerd
```

**验证（所有节点）：**

```bash
systemctl is-active containerd buildkit
nerdctl --version
runc --version
```

---

### 1.8 安装镜像仓库

#### 1.8.1 分发安装包

**登录 k8sc1 执行：**

> 镜像仓库节点与 k8sc1 同机，直接本地拷贝即可。

```bash
mkdir -p /data/k8s_install
cp -r /root/kube-media/04.registry /data/k8s_install/
```

#### 1.8.2 安装

**登录 k8sc1 执行：**

```bash
cd /data/k8s_install/04.registry

# 解压镜像文件
tar -xzf registry-2.8.3.tar.gz

cd docker-registry

# 导入 registry 镜像
nerdctl load -i rg2.8.3.tar
nerdctl images | grep registry

# 生成配置文件
cat > config.yml << 'EOF'
version: 0.1
log:
  level: info
  fields:
    service: registry
storage:
  delete:
    enabled: true
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
    Access-Control-Allow-Origin: ["http://192.168.123.130:5080"]
    Access-Control-Allow-Methods: ["HEAD", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    Access-Control-Allow-Headers: ["Authorization", "Content-Type", "Accept"]
    Access-Control-Max-Age: [1728000]
    Access-Control-Allow-Credentials: [true]
    Access-Control-Expose-Headers: ["Docker-Content-Digest"]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

# 启动 registry
mkdir -p registry-data
nerdctl run -d --name registry --restart always \
    -p 5000:5000 \
    -v $(pwd)/registry-data:/var/lib/registry \
    -v $(pwd)/config.yml:/etc/docker/registry/config.yml \
    registry:2.8.3

# 等待 registry 启动
sleep 10

# 拉取并启动 UI
nerdctl pull registry:5000/joxit/docker-registry-ui:main
nerdctl run -d --name registry-ui-5080 --restart always -p 5080:80 \
    -e REGISTRY_TITLE=Registry \
    -e REGISTRY_URL=http://192.168.123.130:5000 \
    -e DELETE_IMAGES=true \
    registry:5000/joxit/docker-registry-ui:main
```

**验证：**
```bash
nerdctl ps | grep registry
curl -s http://192.168.123.130:5000/v2/_catalog
```

---

### 1.9 初始化 K8S 集群

**登录 k8sc1 执行：**

```bash
# 配置 kubelet 数据目录
mkdir -p /tmp/k8s
echo "KUBELET_EXTRA_ARGS='--root-dir=/data/k8s_install/kubelet_root'" > /etc/sysconfig/kubelet


# 生成 kubeadm 配置文件（单栈模式）
cat > /tmp/k8s/cluster.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.123.130"
  bindPort: 6443
nodeRegistration:
  imagePullPolicy: IfNotPresent
  taints: null
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: /data/k8s_install/etcd_backup
imageRepository: registry:5000/registry.k8s.io
kind: ClusterConfiguration
kubernetesVersion: 1.30.14
controlPlaneEndpoint: "k8sc1:6443"
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/16
scheduler: {}
EOF

# 初始化集群
kubeadm init --upload-certs --config /tmp/k8s/cluster.yaml

# 配置 kubectl
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

**记录 join 命令：**

```bash
# 控制节点 join 命令（含 --control-plane）

# 工作节点 join 命令
```

> **重要：** 请将上述两条 join 命令记录下来，步骤 1.11 和 1.12 需要使用。

**验证：**
```bash
kubectl get nodes
kubectl get po -n kube-system
```

---

### 1.10 修改证书有效期为 100 年

**登录 k8sc1 执行：**

```bash
# 在 kube-controller-manager 配置中添加证书签名时长参数
sed -i '/use-service-account-credentials/a\    - --cluster-signing-duration=867240h0m0s' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml

# 等待 kube-controller-manager 自动重启
sleep 30
```

**验证：**
```bash
kubectl get po -n kube-system | grep kube-controller-manager
```

---

### 1.11 添加从控制节点

**登录 k8sc2 执行：**

```bash
# 使用步骤 1.9 中记录的控制节点 join 命令（含 --control-plane --certificate-key）
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:<实际哈希值> \
    --control-plane --certificate-key <实际证书密钥>

# 配置 kubectl
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

**登录 k8sc3 执行：**

```bash
# 同上
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:<实际哈希值> \
    --control-plane --certificate-key <实际证书密钥>

mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

**在 k8sc1 上验证：**
```bash
kubectl get nodes
# 应看到 k8sc1、k8sc2、k8sc3
```

---

### 1.12 添加工作节点

**登录所有工作节点执行：**

```bash
# 使用步骤 1.9 中记录的工作节点 join 命令
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:<实际哈希值>
```

**在 k8sc1 上验证：**
```bash
kubectl get nodes
# 应看到 9 个节点，状态为 NotReady（等待 CNI 安装）
```

---

### 1.13 安装 CNI 插件 - Flannel

**登录 k8sc1 执行：**

```bash
# 修改 Flannel 配置中的 Pod 网段
FLANNEL_FILE="/root/kube-media/03.setup_file/kube-flannel.yml"
sed -i 's|"Network": ".*"|"Network": "10.244.0.0/16"|' "$FLANNEL_FILE"

# 安装 Flannel
kubectl apply -f "$FLANNEL_FILE"
```

**验证：**
```bash
kubectl get po -n kube-flannel
kubectl get nodes
# 所有 9 个节点应变为 Ready
```

---

> **阶段二完成！所有 K8S 基础组件已就绪。**

---

## 阶段三：生态系统组件安装

> 以下组件通过 `config/cluster.yaml` 中 `ecosystem` 配置控制启用/禁用。
>
> 默认启用：kubemate\_ui、nfs、traefik、prometheus、coredns\_update、kubectl\_permission、etcd\_backup
>
> 默认禁用：elasticsearch、loki、openebs、alloy、minio、metrics\_server、f5\_ha、redis\_sentinel、traefik\_cleanup、log\_cleanup
>
> 禁用的组件标注为"可选"，按需执行即可。

---

### 3.1 创建命名空间

**登录 k8sc1 执行：**

```bash
kubectl apply -f /root/kube-media/03.setup_file/allyaml/0.kubemate-namespace.yaml
```

**验证：**
```bash
kubectl get namespace | grep kubemate-system
```

---

### 3.2 安装 kubemate 管理界面

**登录 k8sc1 执行：**

```bash
KUBEMATE_FILE="/root/kube-media/03.setup_file/allyaml/1.kubemate.yml"

# 修改 hostAliases 中的 IP 为主控节点 IP
sed -i "s/- ip: .*/- ip: 192.168.123.130/" "$KUBEMATE_FILE"

# 安装（执行两遍，避免 CRD 未就绪错误）
kubectl apply -f "$KUBEMATE_FILE"
sleep 5
kubectl apply -f "$KUBEMATE_FILE"
```

**验证：**
```bash
kubectl get po -n kubemate-system | grep kubemate
# 访问地址: http://192.168.123.130:30088
```

---

### 3.3 安装 NFS 插件

#### 3.3.1 配置 NFS 服务器导出

**登录 NFS 服务器（默认 k8sw1）执行：**

```bash
mkdir -p /data/nfs_root

# 添加 NFS 导出条目（如不存在则添加）
grep -qF '/data/nfs_root' /etc/exports 2>/dev/null || \
    echo '/data/nfs_root *(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports

# 生效导出配置
exportfs -ra
systemctl restart nfs-server
```

#### 3.3.2 安装 NFS Provisioner

**登录 k8sc1 执行：**

```bash
helm install nfs-subdir-external-provisioner \
    /root/kube-media/03.setup_file/allyaml/nfs-subdir-external-provisioner \
    --set image.repository=registry:5000/nfs/nfs-subdir-external-provisioner \
    --set image.tag="v4.0.2" \
    --set nfs.server=192.168.123.21 \
    --set nfs.path=/data/nfs_root \
    --set storageClass.name=nfs-storage \
    --set storageClass.defaultClass=true
```

#### 3.3.3 工作节点挂载 NFS

**登录除k8sw1所有节点执行：**

```bash
mkdir -p /data/nfs_root

# 添加 fstab 条目（如不存在则添加）
grep -q '192.168.123.21:/data/nfs_root' /etc/fstab 2>/dev/null || \
    echo '192.168.123.21:/data/nfs_root /data/nfs_root nfs defaults 0 0' >> /etc/fstab

# 挂载
mount -t nfs 192.168.123.21:/data/nfs_root /data/nfs_root
```

**验证（k8sc1）：**
```bash
kubectl get po -n kubemate-system | grep nfs
kubectl get sc
# 应看到 nfs-storage StorageClass
```

---

### 3.4 安装 Elasticsearch + Skywalking（可选，默认禁用）

#### 3.4.1 安装 Elasticsearch

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/allyaml
kubectl apply -f 2.es-crds.yml
kubectl apply -f 2.es-operator.yml
kubectl apply -f 2.es-skywalking.yml
```

**验证：**
```bash
kubectl get po -A | grep es-skywalking
```

#### 3.4.2 安装 Skywalking

**登录 k8sc1 执行：**

```bash
# 1) 获取 Elasticsearch 密码
kubectl get -n kubemate-system secret es-skywalking-es-elastic-user \
    -o go-template='{{.data.elastic | base64decode}}'

# 2) 编辑 Skywalking 配置，将第 74-76 行的 ES_PASSWORD 替换为上一步获取的密码
vi /root/kube-media/03.setup_file/allyaml/3.skywalking-es.yml

# 3) 安装
kubectl apply -f /root/kube-media/03.setup_file/allyaml/3.skywalking-es.yml
```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep skywalking
# skywalking-oap 启动较慢，需多等一会儿
```

---

### 3.5 安装 Loki（可选，默认禁用）

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/v1.30.14/helmapp
helm install -n kubemate-system -f values.yaml ./loki-5.45.0.tgz
```

> 如使用本地磁盘存储 Loki 数据，**登录所有工作节点执行：**
> ```bash
> mkdir -p /data/loki_root
> chown -R 10001:10001 /data/loki_root
> ```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep loki
```

---

### 3.6 安装 Traefik + Traefik Mesh

#### 3.6.1 安装 Traefik

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/allyaml
kubectl apply -f 5.traefki-ds.yaml
kubectl apply -f 6.logfmt-manage.yml
```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep traefik
```

#### 3.6.2 安装 Traefik Mesh

**登录 k8sc1 执行：**

```bash
kubectl apply -f /root/kube-media/03.setup_file/allyaml/5-1.traefik-mesh.yml
```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep traefik-mesh
```

---

### 3.7 安装 Prometheus

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/v1.30.14/prometheus

# 给工作节点打标签（用于监控组件调度）
kubectl label node k8sw1 k8sw2 prom=true --overwrite=true

# 应用本地持久化存储
kubectl apply -f promlocal-pv.yaml

# 按顺序安装组件
kubectl apply -f 1-crd
kubectl apply -f 2-prometheusOperator
kubectl apply -f 3-prometheus
kubectl apply -f 4-nodeExporter
kubectl apply -f 5-kubeStateMetrics
kubectl apply -f 6-alertmanager
kubectl apply -f 8-metrics-server-ha.yaml
kubectl apply -f kubernetesControlPlaneRule
kubectl apply -f process-exporter.yaml
```

**验证：**
```bash
kubectl get pod -n kubemate-monitoring-system
```

---

### 3.8 安装 OpenEBS 存储系统（可选，默认禁用）

> OpenEBS 是 Kubernetes 原生存储系统，提供动态存储分配功能。

#### 3.8.1 控制节点创建存储目录

**登录所有控制节点执行：**

```bash
mkdir -p /data/openebs-root
```

#### 3.8.2 安装 OpenEBS

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/v1.30.14/helmapp/openebs

# 1. 应用 StorageClass
kubectl apply -f openebssc.yaml

# 2. 安装 OpenEBS
helm install openebs -n kubemate-system -f openebs-values.yaml ./openebs-4.2.0.tgz
```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep openebs
kubectl get sc | grep openebs
```

---

### 3.9 安装 Grafana Alloy 可观测性代理（可选，默认禁用）

> Grafana Alloy 是新一代可观测性数据采集代理，替代 Grafana Agent。

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/v1.30.14/helmapp/alloy

# 1. 创建 ConfigMap（从配置文件）
kubectl create cm -n kubemate-system --from-file=congfig.alloy=alloy.config

# 2. 安装 Alloy
helm install alloy -n kubemate-system -f alloy-values.yaml ./alloy-1.4.0.tgz
```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep alloy
```

---

### 3.10 安装 MinIO 对象存储（可选，默认禁用）

> MinIO 是高性能对象存储系统，兼容 S3 API。

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/v1.30.14/helmapp/minio

# 1. 安装 MinIO Operator（需先修改 image 字段为实际镜像地址）
kubectl apply -f minio-operator.yaml

# 2. 等待 Operator 就绪后，获取 token
kubectl get secret -n kubemate-system console-sa-secret -o jsonpath='{.data.token}' | base64 -d

# 3. 使用浏览器访问 MinIO Console 进行实例创建
# 地址：http://<k8sc1_ip>:<minio_console_port>
# 使用步骤 2 获取的 token 登录
```

**验证：**
```bash
kubectl get pod -n kubemate-system | grep minio
kubectl get deployment -n kubemate-system | grep minio-operator
```

---

### 3.11 更新 CoreDNS 配置

> 依赖 Traefik 已安装。

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/allyaml

# 应用 CoreDNS 更新
kubectl apply -f coredns-update.yml
kubectl rollout restart -n kube-system deployment coredns
sleep 5
kubectl rollout restart deployment/traefik-mesh-controller -n kubemate-system

# 配置 CoreDNS 反亲和性（分散到不同节点）
kubectl edit deployment coredns -n kube-system
# 在 spec.template.spec 下添加：
```

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: k8s-app
            operator: In
            values:
            - kube-dns
        topologyKey: kubernetes.io/hostname
```

**验证：**
```bash
kubectl get pod -n kube-system | grep coredns
```

---

### 3.12 安装 Metrics Server（可选，默认禁用）

**登录 k8sc1 执行：**

```bash
sh /root/kube-media/03.setup_file/mertics-server/mertics-server-install.sh amd64
```

**验证：**
```bash
kubectl get pod -n kube-system | grep metrics-server
kubectl top nodes
```

---

### 3.13 配置普通用户 kubectl 权限

**登录 k8sc1 执行：**

```bash
# 复制 kubeconfig 到普通用户目录
cp -r $HOME/.kube /home/appusr/
chown -R appusr:appusr /home/appusr/.kube/
```

**验证：**
```bash
su - appusr -c "kubectl get nodes"
```

---

### 3.14 配置 F5 高可用（可选，默认禁用）

**登录所有控制节点执行：**

```bash
# 编辑 /etc/hosts，将 k8sc1 的 IP 改为当前中心 F5 的 IP
vi /etc/hosts
```

**验证：**
```bash
cat /etc/hosts | grep k8sc1
# 应该看到 F5 的 IP 地址
```

---

### 3.15 安装 Redis 哨兵模式（可选，默认禁用）

**登录 k8sc1 执行：**

```bash
cd /root/kube-media/03.setup_file/allyaml/redis

kubectl create ns redis-sentinel
kubectl apply -f redis-sentinel/redis-pv.yml
kubectl apply -f redis-sentinel/storageclass.yml
helm install -n redis-sentinel redis-ha allyaml/redis-ha
```

**验证：**
```bash
kubectl get pod -n redis-sentinel
```

---

### 3.16 配置定时任务

#### 3.16a ETCD 备份定时任务

**登录所有控制节点执行：**

```bash
# 创建日志目录
mkdir -p /data/crontab_task/etcdbak

# 添加 crontab 条目（1 代表主中心，2 代表副中心）
(crontab -l 2>/dev/null; echo "10 2 * * * nohup sh /root/kube-media/05.crontab/etcdbak.sh 1 >> /data/crontab_task/etcdbak/etcdbak.log &") | crontab -
```

**验证：**
```bash
crontab -l
```

#### 3.16b Traefik 清理定时任务（可选，默认禁用）

**登录所有控制节点执行：**

```bash
(crontab -l 2>/dev/null; echo "0 2 * * * nohup sh /root/kube-media/05.crontab/traefikClear.sh >> /root/kube-media/05.crontab/traefikClear.log &") | crontab -
```

**验证：**
```bash
crontab -l
```

#### 3.16c 日志清理定时任务（可选，默认禁用）

**登录所有工作节点执行：**

```bash
(crontab -l 2>/dev/null; echo "0 2 * * * nohup sh /root/kube-media/05.crontab/logback.sh >> /root/kube-media/05.crontab/logback.log &") | crontab -
```

**验证（所有工作节点）：**
```bash
crontab -l
```

---

> **阶段三完成！所有生态系统组件已就绪。**
