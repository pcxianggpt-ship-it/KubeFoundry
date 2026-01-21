# K8S 安装命令清单

## 部署顺序概览

### 第一阶段：K8S底座安装
1. **服务器规划** - 确认节点配置和网络规划
2. **前置检查与准备**
   - 2.1 初始化参数配置
   - 2.2 检查配置文件完整性
   - 2.3 检查必要工具安装
     - 检查本地必要工具（ssh、scp、rsync、yaml、jq、bc）
     - 检查配置文件中指定的工具路径
     - 检查SSH连接（到所有节点）
3. **安装k8s底座**
   - 3.1 配置本地yum源（k8sc1）
   - 3.2 配置SSH免密登录（可选）
   - 3.3 配置本地k8s repo源客户端（所有节点）
   - 3.4 安装K8s依赖包（所有控制平面和工作节点）
   - 3.5 替换kubeadm为支持100年证书版本（k8sc1）
   - 3.6 环境配置（所有节点）
     - 3.6.1 修改DNS
     - 3.6.2 修改网络配置（IPv6）
     - 3.6.3 修改主机名
     - 3.6.4 修改open files参数
     - 3.6.5 配置环境变量
   - 3.7 安装containerd（所有节点）
   - 3.8 安装镜像仓库（registry节点）
   - 3.9 安装Kubernetes
     - 3.9.1 初始化K8S集群（k8sc1）
     - 3.9.2 添加K8S控制节点（k8sc2、k8sc3）
     - 3.9.3 添加K8S工作节点（k8sw1-k8sw6）
     - 3.9.4 安装CNI插件-Flannel（k8sc1）

### 第二阶段：Kubemate及生态组件安装
4. **Kubemate安装**（以下操作除非特别说明，均在k8sc1执行）
   - 4.1 创建命名空间
   - 4.2 安装kubemate管理界面
   - 4.3 安装NFS插件
   - 4.4 安装elasticsearch
   - 4.5 安装skywalking
   - 4.6 安装loki
   - 4.7 安装traefik
   - 4.8 安装traefik-mesh
   - 4.9 安装prometheus
   - 4.10 更新coredns配置
   - 4.11 安装metrics-server
   - 4.12 配置普通用户kubectl权限
   - 4.13 配置F5 master高可用（所有控制节点）
   - 4.14 安装redis哨兵模式（可选）
   - 4.15 定时任务
     - 4.15.1 ETCD备份
     - 4.15.2 Traefik清理
     - 4.15.3 应用日志清理（所有工作节点）

---

# 1 服务器规划

## 1.控制节点

| 主机名   | ip         | ipv6        | 角色及功能                 |
| -------- | ---------- | ----------- | -------------------------- |
| k8sc1    | 10.3.66.18 | fd00:42::18 | 控制平面（主）、repo源服务 |
| k8sc2    | 10.3.66.19 | fd00:42::19 | 控制平面（从）             |
| k8sc3    | 10.3.66.20 | fd00:42::20 | 控制平面（从）             |
| k8sw1    | 10.3.66.21 | fd00:42::21 | 工作节点、nfs服务器        |
| k8sw2    | 10.3.66.22 | fd00:42::22 | 工作节点                   |
| k8sw3    | 10.3.66.23 | fd00:42::23 | 工作节点                   |
| k8sw4    | 10.3.66.24 | fd00:42::24 | 工作节点                   |
| k8sw5    | 10.3.66.25 | fd00:42::25 | 工作节点                   |
| k8sw6    | 10.3.66.26 | fd00:42::26 | 工作节点                   |
| registry | 10.3.66.20 | fd00:42::20 | 镜像仓库                   |



# 2. 前置检查与准备

## 2.1 初始化参数配置

执行机器：管理节点（本地执行）

```bash
# 1. 加载配置文件
# 读取 config/config.yaml 配置文件
# 解析 YAML 格式的配置参数

# 2. 验证配置文件格式
# 检查 YAML 语法是否正确
# 检查必需参数是否存在

# 3. 初始化全局变量
# 从配置文件读取 K8S 版本、网络参数等
# 设置部署阶段的默认值

# 4. 显示配置摘要
echo "======================================"
echo "K8S 集群部署配置"
echo "======================================"
echo "K8S 版本: ${k8s_version}"
echo "Pod 网段: ${pod_subnet}"
echo "Service 网段: ${service_subnet}"
echo "控制节点数量: ${control_node_count}"
echo "工作节点数量: ${worker_node_count}"
echo "======================================"
```

#### 4. 验证安装结果

```bash
# 检查配置文件是否成功加载
if [ -z "${k8s_version}" ]; then
    echo "【ERROR】: 配置文件加载失败"
    exit 1
fi

echo "【INFO】: 配置参数初始化完成"
```

---

## 2.2 检查配置文件完整性

执行机器：管理节点（本地执行）

```bash
# 1. 检查配置文件是否存在
if [ ! -f "config/config.yaml" ]; then
    echo "【ERROR】: 配置文件不存在: config/config.yaml"
    exit 1
fi

echo "【INFO】: 配置文件检查通过"

# 2. 检查必需的配置项
required_params=(
    "k8s.version"
    "network.cluster.pod_subnet"
    "network.cluster.service_subnet"
    "network.control_plane.endpoint"
)

for param in "${required_params[@]}"; do
    # 使用 config_get 方法检查参数
    value=$(config_get ".$param")

    if [ -z "$value" ]; then
        echo "【ERROR】: 必需参数缺失: $param"
        exit 1
    fi
done

echo "【INFO】: 必需参数检查通过"

# 3. 验证 IP 地址格式
echo "【INFO】: 验证节点 IP 地址格式..."
all_nodes=$(config_get_all_nodes)
for node in $all_nodes; do
    node_ip=$(config_get_node "$node" "ip")

    # 验证 IPv4 格式
    if ! validate_ip "$node_ip"; then
        echo "【ERROR】: 节点 $node 的 IP 地址格式错误: $node_ip"
        exit 1
    fi
done

echo "【INFO】: IP 地址格式验证通过"

# 4. 验证端口号有效性
echo "【INFO】: 验证端口号..."
api_server_port=$(config_get ".network.api_server_port" "6443")
if ! validate_port "$api_server_port"; then
    echo "【ERROR】: API Server 端口号无效: $api_server_port"
    exit 1
fi

echo "【INFO】: 端口号验证通过"

# 5. 验证文件路径可访问性
echo "【INFO】: 验证文件路径..."
repo_source=$(config_get ".repo.source_path")
if [ -n "$repo_source" ] && [ ! -f "$repo_source" ]; then
    echo "【WARN】: YUM 源文件不存在: $repo_source"
fi

echo "【INFO】: 配置文件完整性检查完成"
```

#### 4. 验证安装结果

```bash
# 检查配置验证是否通过
if [ $? -eq 0 ]; then
    echo "【SUCCESS】: 配置文件完整性验证通过"
else
    echo "【ERROR】: 配置文件完整性验证失败"
    exit 1
fi
```

---

## 2.3 检查必要工具安装

执行机器：管理节点（本地执行）

```bash
# 1. 检查本地必要工具
echo "【INFO】: 检查本地必要工具..."

local_tools=("ssh" "scp" "rsync" "yaml" "jq" "bc")

for tool in "${local_tools[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "【ERROR】: 本地缺少必要工具: $tool"
        echo "请先安装: yum install -y $tool"
        exit 1
    fi
    echo "【INFO】: ✓ $tool 已安装"
done

echo "【SUCCESS】: 本地工具检查通过"

# 2. 检查配置文件中指定的工具路径
echo "【INFO】: 检查配置文件中指定的工具..."

# 检查 helm 工具
helm_path=$(config_get ".tools.helm_path" "/usr/local/bin/helm")
if [ -n "$helm_path" ] && [ ! -f "$helm_path" ]; then
    echo "【WARN】: helm 未找到: $helm_path"
fi

echo "【INFO】: 工具路径检查完成"

# 3. 检查 SSH 连接（到所有节点）
echo "【INFO】: 检查 SSH 连接..."
all_nodes=$(config_get_all_nodes)
failed_nodes=()

for node in $all_nodes; do
    node_ip=$(config_get_node "$node" "ip")

    if ! ssh_check_connection "$node_ip"; then
        echo "【ERROR】: 无法连接到节点 $node ($node_ip)"
        failed_nodes+=("$node")
    else
        echo "【INFO】: ✓ 节点 $node ($node_ip) SSH 连接正常"
    fi
done

if [ ${#failed_nodes[@]} -gt 0 ]; then
    echo "【ERROR】: 以下节点 SSH 连接失败:"
    printf '%s\n' "${failed_nodes[@]}"
    echo "请检查:"
    echo "1. 节点是否启动"
    echo "2. SSH 服务是否运行"
    echo "3. 网络连通性"
    echo "4. SSH 密钥是否配置"
    exit 1
fi

echo "【SUCCESS】: SSH 连接检查通过"

# 4. 生成检查报告
echo ""
echo "======================================"
echo "前置检查报告"
echo "======================================"
echo "配置文件: ✓ 通过"
echo "配置参数: ✓ 通过"
echo "IP 地址格式: ✓ 通过"
echo "端口号: ✓ 通过"
echo "本地工具: ✓ 通过"
echo "SSH 连接: ✓ 通过"
echo "======================================"
echo ""
```

#### 3. 验证安装结果

```bash
# 所有检查应该通过，否则退出
if [ $? -eq 0 ]; then
    echo "【SUCCESS】: 前置检查全部通过，可以开始部署"
else
    echo "【ERROR】: 前置检查失败，请修复错误后重试"
    exit 1
fi
```

---

# 3. 安装k8s底座

## 3.1 配置本地yum源

执行机器：控制平面（主）

```

repo_source_name="$1"

# 1. 验证/var/www/html/$1文件是否存在
if [ ! -f "$repo_source_name" ]; then
    echo "【ERROR】: YUM源文件不存在: $repo_source_name"
    exit 1
fi

echo "【INFO】: 找到YUM源文件: $repo_source_name"

mkdir -p /var/www/html/

tar -zxf $repo_source_name -C /var/www/html/

# 2. 添加.repo文件
cat << EOF | tee /etc/yum.repos.d/k8s.repo > /dev/null
[k8s-yum]
name=rhel7
baseurl=file:///var/www/html/repo/
enabled=1
gpgcheck=0
EOF


# 3. 刷新缓存
yum -q clean all
yum -q makecache

# 4. 验证k8s yum源是否存在，能找到kubelet说明yum源部署成功
echo "【INFO】: 验证k8s yum源..."

yum -q search kubelet


# 5. 安装httpd并开机自启动服务

yum -yq install httpd
systemctl enable httpd --now


# 关闭防火墙
echo "【INFO】: 关闭防火墙服务"
systemctl stop firewalld >/dev/null 2>&1
systemctl disable firewalld >/dev/null 2>&1

```



## 3.2 配置SSH免密登录



## 3.3 配置本地k8s repo源客户端

执行机器：除k8sc1外，所有服务器执行

```
cat <<EOF | tee /etc/yum.repos.d/k8s-http.repo > /dev/null
[k8s-repo]
name=http
baseurl=http://k8sc1/repo
enabled=1
gpgcheck=0
EOF

yum -q clean all 
yum -q makecache
```



## 3.4 安装K8s依赖包

执行机器：所有控制平面和所有工作节点安装

```
yum install -y cri-tools kubeadm kubectl kubelet kubernetes-cni nfs
```



## 3.5 替换kubeadm为支持100年证书版本

执行机器：仅在k8sc1上执行

```
# 确保临时目录存在
mkdir -p /tmp/k8s

# 备份原始kubeadm
cp /usr/bin/kubeadm /tmp/k8s/kubeadm_bak
local kubeadm_100y_file="$data_path/01.rpm_package/kubeadm-$k8s_version-100y-$arch_type"
scp "$kubeadm_100y_file" /usr/bin/kubeadm
```



## 3.6 环境配置

### 3.6.1 修改DNS

执行机器： 1. 所有控制节点、工作节点执行命令

```bash
# 1. 查看网卡中的GATEWAY地址
cat /etc/sysconfig/network-scripts/ifcfg-ens192

# 2. 修改DNS为GATEWAY地址
vi /etc/systemd/resolved.conf
# 修改 [Resolve] 部分，将 DNS= 设置为 GATEWAY 地址
```

### 3.6.2 修改网络配置（如需配置ipv6双栈网络时才进行配置）

执行机器：1.控制节点执行命令 2. 工作节点执行命令 3. 镜像仓库执行命令

IPV6ADDR 为配置文件中的Ipv6地址

```
# 1. 查看网卡中的GATEWAY地址
cat /etc/sysconfig/network-scripts/ifcfg-ens192

# 2. 修改DNS为GATEWAY地址
vi /etc/systemd/resolved.conf
# 修改 [Resolve] 部分，将 DNS= 设置为 GATEWAY 地址

# 3. 修改IPv6配置
vi /etc/sysconfig/network-scripts/ifcfg-ens192
# 添加以下配置：
# IPV6INIT=yes
# IPV6_AUTOCONF=no
# IPV6ADDR=fd00:42::171
# IPV6_DEFAULTGW=fd00::1
# IPV6_DEFROUTE=yes
# IPV6_FAILURE_FATAL=no
# IPV6_ADDR_GEN_MODE=none

# 4. 重启网络
systemctl daemon-reload
systemctl restart systemd-resolved
systemctl enable systemd-resolved
systemctl restart NetworkManager
```

#### 4. 验证安装结果

```bash
# 验证IPv6配置
ip a
# 确认IPv6地址配置正确
# 如果重启网络后IPv6数值没有变化，需要重启服务器
```

---

### 3.6.3 修改主机名

#### 1. 控制节点执行命令

**k8sc1 节点执行：**

```bash
hostnamectl set-hostname k8sc1
su - root
```

**k8sc2 节点执行：**
```bash
hostnamectl set-hostname k8sc2
su - root
```

**k8sc3 节点执行（镜像仓库）：**
```bash
hostnamectl set-hostname k8sc3
su - root
```

**所有节点执行：**

```bash
# 修改/etc/hosts
cat << EOF >> /etc/hosts
10.3.66.18 k8sc1
10.3.66.19 k8sc2
10.3.66.20 k8sc3
10.3.66.21 k8sw1
10.3.66.22 k8sw2
10.3.66.23 k8sw3
10.3.66.24 k8sw4
10.3.66.25 k8sw5
10.3.66.26 k8sw6
10.3.66.20 registry
EOF
```

#### 2. 工作节点执行命令

**k8sw1 节点执行：**
```bash
hostnamectl set-hostname k8sw1
su - root
```

**k8sw2 节点执行：**
```bash
hostnamectl set-hostname k8sw2
su - root
```

**k8sw3 节点执行：**
```bash
hostnamectl set-hostname k8sw3
su - root
```

**k8sw4 节点执行：**
```bash
hostnamectl set-hostname k8sw4
su - root
```

**k8sw5 节点执行：**
```bash
hostnamectl set-hostname k8sw5
su - root
```

**k8sw6 节点执行：**
```bash
hostnamectl set-hostname k8sw6
su - root
```

**所有工作节点执行：**
```bash
# 修改/etc/hosts
cat << EOF >> /etc/hosts
10.3.66.18 k8sc1
10.3.66.19 k8sc2
10.3.66.20 k8sc3
10.3.66.21 k8sw1
10.3.66.22 k8sw2
10.3.66.23 k8sw3
10.3.66.24 k8sw4
10.3.66.25 k8sw5
10.3.66.26 k8sw6
10.3.66.20 registry
EOF
```



#### 3. 验证安装结果

```bash
# 在所有节点上验证主机名
hostname

# 验证/etc/hosts配置
cat /etc/hosts
# 确认配置成功，如果执行了多遍，需删除重复内容
```

---

### 3.6.4 修改open files参数

执行机器：所有节点执行

```bash
# 所有控制节点执行
vi /etc/security/limits.conf
# 添加以下内容：
# * soft nofile 65535
# * hard nofile 65535
```

#### 

---

### 3.6.5 配置环境变量

执行机器：所有节点执行

```bash
# 所有控制节点执行

# 1. 设置参数

# 2. 关闭swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# 3. 关闭防火墙
systemctl stop firewalld > /dev/null 2>&1
systemctl disable firewalld > /dev/null 2>&1

# 4. 卸载podman等容器
yum remove podman -y > /dev/null 2>&1
yum remove containerd -y > /dev/null 2>&1

# 5. 配置DNS
sed -i '/nameserver/d' /etc/resolv.conf
echo "8.8.8.8 nameserver" >> /etc/resolv.conf

# 6. 转发ipv4 ipv6并让iptables看到桥接流量
cat << EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 7. 修改sysctl.conf
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-iptables/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-ip6tables/d' /etc/sysctl.conf
echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf

# 8. 配置IPv6
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.forwarding/d' /etc/sysctl.conf
echo net.ipv6.conf.all.disable_ipv6=0 >> /etc/sysctl.conf
echo net.ipv6.conf.default.disable_ipv6=0 >> /etc/sysctl.conf
echo net.ipv6.conf.lo.disable_ipv6=0 >> /etc/sysctl.conf
echo net.ipv6.conf.all.forwarding=1 >> /etc/sysctl.conf
echo net.ipv6.conf.default.forwarding=1 >> /etc/sysctl.conf

# 9. 应用sysctl配置
sysctl --system > /dev/null

# 10. 启用systemd-resolved
systemctl enable systemd-resolved > /dev/null 2>&1
```



---



## 3.7 安装containerd

执行机器：所有节点执行

```bash
# 所有控制节点执行
cd /tmp/k8s/02.container_runtime

# 解压containerd-1.7.18-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.18-linux-amd64.tar.gz

# 创建containerd自启service
cp containerd.service /etc/systemd/system/containerd.service

# 安装runc
install -m 755 runcv1.3.3.amd64 /usr/local/sbin/runc

# 安装cni-plugins
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.8.0.tgz

# 生成默认配置文件
mkdir -p /etc/containerd
cp config-1.7.18.toml /etc/containerd/config.toml

# 安装buildkit
tar Cxzvf /usr/local buildkit-v0.25.2.linux-amd64.tar.gz

# 创建buildkit自启服务并启动
cp buildkit.s* /etc/systemd/system/
systemctl daemon-reload
systemctl enable buildkit.service --now

# 安装nerdctl
tar -zxf nerdctl-2.2.0-linux-amd64.tar.gz
chmod +x nerdctl
mv nerdctl /usr/local/bin/

# 配置镜像仓库地址（使用变量）
mkdir -p /etc/containerd/certs.d/\$registry:5000
cat > /etc/containerd/certs.d/\$registry:5000/hosts.toml <<EOF
server = "http://\$registry:5000"

[host."http://\$registry:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 配置镜像仓库地址（使用域名）
mkdir -p /etc/containerd/certs.d/registry:5000
cat > /etc/containerd/certs.d/registry:5000/hosts.toml <<EOF
server = "http://registry:5000"

[host."http://registry:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 启动containerd
systemctl daemon-reload
systemctl enable --now containerd
```



---

## 3.8 安装镜像仓库

### 3.8.1 安装registry免密

执行机器：镜像仓库执行

```bash

# 2. 安装镜像仓库
sh /data/k8s_install/04.registry/registry_install.sh 10.3.66.20
# 参数说明：第一个参数为镜像仓库的IP地址
```

---



## 3.9 安装Kubernetes



### 3.9.1 初始化K8S集群

#### 1. 控制节点执行命令

**仅在k8sc1（第一个控制节点）上执行：**

```bash
# 1. 设置集群初始化文件
cd /data/k8s_install/03.setup_file
vi cluster.yaml
# 修改以下配置：
# - controlPlaneEndpoint: 设置为控制平面地址（如：10.3.66.18:6443）
# - advertiseAddress: 修改为本机IP
# - podSubnet: Pod网络网段
# - serviceSubnet: Service网络网段

# 2. 配置kubelet路径
echo KUBELET_EXTRA_ARGS='--root-dir=/data/kubelet_root' > /etc/sysconfig/kubelet

# 3. 初始化并启动集群
cd /data/k8s_install/03.setup_file
kubeadm init --upload-certs --config cluster.yaml
# 记录输出中的kubeadm join命令，供后续添加节点使用

# 4. 配置kubectl
mkdir -p $HOME/.kube
sudo scp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

# 5. 将kubeadm join命令保存到本地（重要！）
# 从第3步的输出中复制以下命令到本地文件：
# - 控制节点加入命令（包含--control-plane参数）
# - 工作节点加入命令（不包含--control-plane参数）
```

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行
kubectl get nodes
# 应该看到k8sc1节点，状态为NotReady（正常，需要安装CNI插件）

kubectl get pods -A
# 查看所有命名空间的Pod状态
# coredns可能显示为Pending，需要安装CNI插件后才会正常运行
```

---

### 3.9.2 修改证书有效期

#### 1. 控制节点执行命令

```bash
# 在k8sc1控制节点上执行
vi /etc/kubernetes/manifests/kube-controller-manager.yaml
# 在 spec.containers.command 下面最后一行添加：
# - --cluster-signing-duration=867240h0m0s
# 保存并退出，kube-controller-manager会自动重启
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行
kubeadm certs check-expiration
# 查看证书有效期，应该显示为100年（或配置的时长）
```

---

### 3.9.3 添加K8S控制节点

> **说明：** 搭建高可用时执行，单master节点部署可跳过该步骤

#### 1. 控制节点执行命令

执行机器： k8sc2和k8sc3节点执行（一台执行完后再执行另一台）

```bash
# 使用3.9.1章节中保存的kubeadm join控制节点命令
# 示例（实际命令以k8sc1初始化输出为准）：
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:be3037375048669762a18c0d820994613d4611c768f524fca5d808ca3caf47da \
  --control-plane --certificate-key 8cc3bc5f73f00cfb37c77413a73c87513dad3142ab3c5052a124387efc8b8742

# 配置kubectl
mkdir -p $HOME/.kube
sudo scp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf
```



---

### 3.9.4 添加K8S工作节点

#### 1. 控制节点执行命令

无需执行（工作节点自己执行join命令）。

#### 2. 工作节点执行命令

**所有工作节点（k8sw1-k8sw6）执行：**

```bash
# 使用3.9.1章节中保存的kubeadm join工作节点命令
# 示例（实际命令以k8sc1初始化输出为准）：
kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:abb882fd3462e84cd1c1f9ecf39ca305f6acb8bd8f2ffb72ccf3cba3341df05e
```

**如果出现证书错误（x509），在工作节点上执行：**

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf
```

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行
kubectl get nodes
# 应该看到所有控制节点和工作节点
# 状态为NotReady是正常的，安装CNI插件后会变为Ready
```

---

### 3.9.5 安装CNI插件-Flannel

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 查看kube-flannel.yml中的网络配置
cd /data/k8s_install/03.setup_file
vi kube-flannel.yml
# 确认网络配置与cluster.yaml中的网段一致

# 2. 安装Flannel
kubectl apply -f /data/k8s_install/03.setup_file/kube-flannel.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

# 验证节点状态
kubectl get nodes
# 所有节点的状态应为Ready

# 验证Pod状态
kubectl get pods -A
# 所有Pod（包括coredns）的状态应为Running或Completed
# kube-flannel-ds Pods应在每个节点上运行
```

**故障排查：**

```bash
# 如果Pod没有正常运行（READY显示为0/1），查看详细信息
kubectl describe pod kube-flannel-ds-xxxx -n kube-flannel
# 查看Events和Logs部分的错误信息
```

---

# 4 Kubemate安装

> **操作说明：** 如无特殊说明，以下所有操作仅在 k8sc1（master1）控制节点上执行。

## 4.1  创建命名空间

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行
kubectl apply -f /data/k8s_install/03.setup_file/allyaml/0.kubemate-namespace.yaml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行
kubectl get namespace
# 应该看到 kubemate-system 命名空间
```

---

## 4.2  安装kubemate管理界面

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 修改配置文件
cd /data/k8s_install/03.setup_file/allyaml
vi 1.kubemate.yml
# 修改第730行，改为k8sc1的IP地址（如：10.3.66.18）

# 2. 安装kubemate（执行两遍，如果出现no matches错误）
kubectl apply -f 1.kubemate.yml
kubectl apply -f 1.kubemate.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 1. 检查Pod状态
kubectl get pods -n kubemate-system
# 所有Pod状态应为Running

# 2. 访问Web界面
# 浏览器访问：http://10.3.66.18:30088
# 默认用户名密码：admin / 000000als
```

---

## 4.3  安装NFS插件

#### 1. 控制节点执行命令

```bash
# 1. 验证系统是否自带nfs
systemctl status nfs-server

# 2. 如果不存在nfs-server，安装nfs（所有控制节点执行）
cd /data/k8s_install/01.rpm_package/nfs
rpm -ivh *.rpm

# 3. 启动nfs-server（所有控制节点执行）
systemctl enable nfs-server && systemctl start nfs-server

# 4. 验证NAS挂载（一般已由系统岗挂载好）
# mount -t nfs 10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root

# 5. 修改nfs配置（仅在k8sc1控制节点执行）
cd /data/k8s_install/03.setup_file/allyaml
vi nfs-value.yaml
# 修改为NAS server提供的IP和访问路径

# 6. 配置开机自动挂载（所有控制节点执行）
vi /etc/fstab
# 添加：10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root nfs defaults 0 0

# 7. 安装helm（仅在k8sc1控制节点执行）
cp /data/k8s_install/03.setup_file/allyaml/linux-amd64/helm /usr/local/bin/helm

# 8. 安装nfs provisioner（仅在k8sc1控制节点执行）
cd /data/k8s_install/03.setup_file/allyaml
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/ -f nfs-value.yaml
```

#### 2. 工作节点执行命令

```bash
# 所有工作节点执行

# 1. 验证系统是否自带nfs
systemctl status nfs-server

# 2. 如果不存在nfs-server，安装nfs
cd /data/k8s_install/01.rpm_package/nfs
rpm -ivh *.rpm

# 3. 启动nfs-server
systemctl enable nfs-server && systemctl start nfs-server

# 4. 配置开机自动挂载
vi /etc/fstab
# 添加：10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root nfs defaults 0 0
```

#### 3. 镜像仓库执行命令

```bash
# 镜像仓库节点执行（同工作节点命令）

# 1. 验证系统是否自带nfs
systemctl status nfs-server

# 2. 如果不存在nfs-server，安装nfs
cd /data/k8s_install/01.rpm_package/nfs
rpm -ivh *.rpm

# 3. 启动nfs-server
systemctl enable nfs-server && systemctl start nfs-server

# 4. 配置开机自动挂载
vi /etc/fstab
# 添加：10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root nfs defaults 0 0
```

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

# 1. 检查nfs provisioner Pod状态
kubectl get pod
# Pod状态应为Running

# 2. 验证NAS挂载
df -h | grep nas_root
# 应该看到挂载的NFS存储
```

---

## 4.4  安装elasticsearch

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f 2.es-crds.yml
kubectl apply -f 2.es-operator.yml
kubectl apply -f 2.es-skywalking.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get po -A | grep es-skywalking
# es-skywalking相关Pod状态应为Running
```

---

## 4.5  安装skywalking

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 获取Elasticsearch密码（保存到本地）
kubectl get -n kubemate-system secret es-skywalking-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'

# 2. 修改skywalking配置文件
cd /data/k8s_install/03.setup_file/allyaml
vi 3.skywalking-es.yml
# 修改第74-76行，将ES_PASSWORD替换为步骤1获取的密码

# 3. 安装skywalking
kubectl delete -f 3.skywalking-es.yml
kubectl apply -f 3.skywalking-es.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep skywalking
# skywalking相关Pod状态应为Running（skywalking-oap启动较慢，需要多等一会儿）
```

---

## 4.6  安装loki

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f 4.loki.yml
kubectl apply -f 4.loki-sec.yml
```

#### 2. 工作节点执行命令

```bash
# 如果使用本地磁盘存储loki数据，所有工作节点执行
mkdir -p /data/loki_root
chown -R 10001:10001 /data/loki_root
```

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep loki
# loki相关Pod状态应为Running
```

---

## 4.7  安装traefik

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f 5.traefki-ds.yaml
kubectl apply -f 5.traefki-ds.yaml
kubectl apply -f 6.logfmt-manage.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep traefik
# traefik相关Pod状态应为Running
```

---

## 4.8  安装traefik-mesh

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f 5-1.traefik-mesh.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep traefik-mesh
# traefik-mesh相关Pod状态应为Running
```

---

## 4.9  安装prometheus

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cd /data/k8s_install/03.setup_file/allyaml/prometheus
kubectl create -f 1-crd.yml
kubectl apply -f 2-namespace.yml
kubectl apply -f 3-rbac.yml
kubectl apply -f 4-prometheus-operator.yml
kubectl apply -f 5-additional-scrape-configs.yml
kubectl apply -f 6-prometheus.yml
kubectl apply -f 7-alertmanager.yml
kubectl apply -f 8-prometheus-rule.yml
kubectl apply -f node-exporter.yml
kubectl apply -f kube-state-metrics.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-monitoring-system
# prometheus相关Pod状态应为Running
```

---

## 4.10  更新coredns配置

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 执行更新脚本
cd /data/k8s_install/03.setup_file/allyaml
kubectl apply -f coredns-update.yml
kubectl rollout restart -n kube-system deployment coredns
sleep 5
kubectl rollout restart deployment/traefik-mesh-controller -n kubemate-system

# 2. 编辑coredns配置
kubectl edit deployment coredns -n kube-system
# 在第40行，spec.template.spec下添加以下内容（注意格式对齐）：
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

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kube-system | grep coredns
# coredns Pod状态应为Running，且分布在不同的节点上
```

---

## 4.11  安装metrics-server

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

sh /data/k8s_install/03.setup_file/mertics-server/mertics-server-install.sh amd64
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n kube-system | grep metrics-server
# metrics-server Pod状态应为Running

kubectl top nodes
# 应该能看到各节点的资源使用情况
```

---

## 4.12  配置普通用户kubectl权限

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cp -r .kube /home/appusr/
chown -R appusr:appusr .kube/
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 切换到普通用户验证
su - appusr
kubectl get nodes
# 应该能正常列出节点信息
```

---

## 4.13  配置F5 master高可用

#### 1. 控制节点执行命令

```bash
# 所有控制节点执行

vi /etc/hosts
# 将k8sc1的IP改为当前中心F5的IP
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 验证hosts文件配置
cat /etc/hosts | grep k8sc1
# 应该看到F5的IP地址
```

---

## 4.14  安装redis哨兵模式

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

cd /data/k8s_install/03.setup_file/allyaml/redis
kubectl create ns redis-sentinel
kubectl apply -f redis-sentinel/redis-pv.yml
kubectl apply -f redis-sentinel/storageclass.yml
helm install -n redis-sentinel redis-ha allyaml/redis-ha
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n redis-sentinel
# redis相关Pod状态应为Running
```

---

## 4.15  定时任务

### 4.15.1 ETCD备份

#### 1. 控制节点执行命令

```bash
# 主副中心的k8sc1控制节点上执行（root权限）

crontab -e
# 添加以下内容：
10 2 * * * nohup sh /data/k8s_install/05.crontab/etcdbak.sh 1 >> /data/crontab_task/etcdbak/etcdbak.log &

# 注意：etcdbak.sh后面的参数：1代表主中心，2代表副中心
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 查看定时任务
crontab -l
# 应该能看到ETCD备份任务

# 查看备份日志
ls -lh /data/crontab_task/etcdbak/
# 应该能看到备份日志文件
```

---

### 4.15.2 Traefik清理

#### 1. 控制节点执行命令

```bash
# 主副中心的k8sc1控制节点上执行（root权限）

crontab -e
# 添加以下内容：
0 2 * * * nohup sh /data/k8s_install/05.crontab/traefikClear.sh >> /data/k8s_install/05.crontab/traefikClear.log &
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 查看定时任务
crontab -l
# 应该能看到Traefik清理任务

# 查看清理日志
cat /data/k8s_install/05.crontab/traefikClear.log
# 应该能看到清理日志
```

---

### 4.15.3 应用日志清理

#### 1. 控制节点执行命令

无需执行。

#### 2. 工作节点执行命令

```bash
# 所有工作节点执行（root权限）

crontab -e
# 添加以下内容：
0 2 * * * nohup sh /data/k8s_install/05.crontab/logback.sh >> /data/k8s_install/05.crontab/logback.log &
```

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在工作节点上验证

# 查看定时任务
crontab -l
# 应该能看到应用日志清理任务

# 查看清理日志
cat /data/k8s_install/05.crontab/logback.log
# 应该能看到清理日志
```

---
