# K8S 安装命令清单

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



# 2.安装k8s底座

## 2.1 配置本地yum源

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



## 2.2 配置SSH免密登录



## 2.3 配置本地k8s repo源客户端

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



## 2.4替换kubeadm为支持100年证书版本

执行机器：仅在k8sc1上执行

```
# 确保临时目录存在
mkdir -p /tmp/k8s

# 备份原始kubeadm
cp /usr/bin/kubeadm /tmp/k8s/kubeadm_bak
local kubeadm_100y_file="$data_path/01.rpm_package/kubeadm-$k8s_version-100y-$arch_type"
scp "$kubeadm_100y_file" /usr/bin/kubeadm
```



## 2.5 安装K8s依赖包

执行机器：所有机器上执行

```
yum install -y cri-tools kubeadm kubectl kubelet kubernetes-cni 
```



## 2.6 环境配置

### 2.6.1 修改DNS

#### 1. 所有控制节点、工作节点执行命令

```bash
# 1. 查看网卡中的GATEWAY地址
cat /etc/sysconfig/network-scripts/ifcfg-ens192

# 2. 修改DNS为GATEWAY地址
vi /etc/systemd/resolved.conf
# 修改 [Resolve] 部分，将 DNS= 设置为 GATEWAY 地址
```

### 2.6.2 修改网络配置（如需配置ipv6双栈网络时才进行配置）

执行机器：1.控制节点执行命令   2. 工作节点执行命令 3. 镜像仓库执行命令

IPV6ADDR 为配置文件中的Ip

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

### 2.3.2 修改主机名

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

### 2.6.3 修改open files参数

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

### 2.3.4 配置环境变量

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



## 2.4 安装containerd

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

## 2.5 安装镜像仓库

### 2.5.1 安装registry免密

执行机器：镜像仓库执行

```bash

# 2. 安装镜像仓库
sh /data/k8s_install/04.registry/registry_install.sh 10.3.66.20
# 参数说明：第一个参数为镜像仓库的IP地址
```

---



## 2.6 安装Kubernetes



### 2.6.1 初始化K8S集群

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

### 2.6.3 修改证书有效期

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

### 2.6.4 添加K8S控制节点

> **说明：** 搭建高可用时执行，单master节点部署可跳过该步骤

#### 1. 控制节点执行命令

执行机器： k8sc2和k8sc3节点执行（一台执行完后再执行另一台）

```bash
# 使用2.6.2章节中保存的kubeadm join控制节点命令
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

### 2.6.5 添加K8S工作节点

#### 1. 控制节点执行命令

无需执行（工作节点自己执行join命令）。

#### 2. 工作节点执行命令

**所有工作节点（k8sw1-k8sw6）执行：**

```bash
# 使用2.6.2章节中保存的kubeadm join工作节点命令
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

### 2.6.6 安装CNI插件-Flannel

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

# 3    Kubemate安装

> **操作说明：** 如无特殊说明，以下所有操作仅在 k8sc1（master1）控制节点上执行。

## 3.1  创建命名空间

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

## 3.2  安装kubemate管理界面

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

## 3.3  创建全局镜像仓库

#### 1. 控制节点执行命令

此步骤在kubemate管理界面中操作：
1. 登录kubemate管理界面（http://10.3.66.18:30088）
2. 进入"保密配置"
3. 添加"全局镜像仓库"
4. 录入镜像仓库地址、用户名和密码

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

在kubemate管理界面中确认全局镜像仓库已添加。

---

## 3.4  安装NFS插件

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

## 3.5  安装elasticsearch

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

## 3.6  安装skywalking

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

## 3.7  安装loki

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

## 3.8  安装traefik

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

## 3.9  安装traefik-mesh

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

## 3.10  安装prometheus

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

## 3.11  更新coredns配置

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

## 3.12  安装metrics-server

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

## 3.13  配置普通用户kubectl权限

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

## 3.14  配置F5 master高可用

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

## 3.15  安装redis哨兵模式

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

## 3.16  安装redis集群

### 3.16.1  创建工作路径

#### 1. 控制节点执行命令

无需执行。

#### 2. 工作节点执行命令

```bash
# 所有工作节点执行

mkdir -p /data/redis_root
```

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在工作节点上验证

ls -ld /data/redis_root
# 目录应该存在
```

---

### 3.16.2  安装redis集群

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 创建命名空间
kubectl create ns redis-opt

# 2. 创建存储卷
cd /data/k8s_install/03.setup_file/allyaml/redis/redis-pvc
kubectl apply -f localstorageclass.yaml
kubectl apply -f redis-pv.yml

# 3. 创建redis-secret
kubectl create secret generic redis-secret -n redis-opt --from-literal=password=Xxkjb_Fxcps_Redis2024

# 4. 安装redis-operator
/data/k8s_install/06.redis-cluster/linux-amd64/helm install -n redis-opt redis-operator /data/k8s_install/06.redis-cluster/allyaml/redis-operator

# 5. 安装redis-cluster
/data/k8s_install/06.redis-cluster/linux-amd64/helm install -n redis-opt redis-cluster /data/k8s_install/06.redis-cluster/allyaml/redis-cluster
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n redis-opt
# 应该看到redis-cluster-leader和redis-cluster-follower的Pod，状态为Running

# 可在kubemate管理界面的"有状态发布"中查看leader和follower状态
```

---

### 3.16.3  修改redis密码

#### 1. 控制节点执行命令

```bash
# 在kubemate管理界面中操作
# 1. 进入"保密配置"，找到redis-secret，修改redis密码

# 2. 修改密码后，通过kubemate界面重启redis集群
# 重启步骤见 3.16.5

# 3. 进入redis-cluster-leader或redis-cluster-follower的Pod终端验证密码
redis-cli
auth <新密码>
# 显示ok即为修改成功
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

在Pod终端中验证新密码能否正常登录。

---

### 3.16.4  卸载redis集群

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 查看安装详情
/data/k8s_install/06.redis-cluster/linux-amd64/helm list -A

# 2. 卸载redis集群
/data/k8s_install/06.redis-cluster/linux-amd64/helm uninstall -n redis-opt redis-cluster
/data/k8s_install/06.redis-cluster/linux-amd64/helm uninstall -n redis-opt redis-operator

# 3. 删除服务器文件（所有工作节点执行）
rm -rf /data/redis_root/*
```

#### 2. 工作节点执行命令

```bash
# 所有工作节点执行

rm -rf /data/redis_root/*
```

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n redis-opt
# 应该没有redis相关的Pod
```

---

### 3.16.5  重启redis集群

#### 1. 控制节点执行命令

```bash
# 在kubemate管理界面中按以下顺序操作：

# 1. 将redis-operator的副本数改为0，等待Pod停止
# 2. 将redis-leader的副本数改为0，等待Pod停止
# 3. 将redis-follower的副本数改为0，等待Pod停止
# 4. 进入/data/redis_root目录，删除目录下所有文件（所有工作节点执行）
# 5. 将redis-operator的副本数改为1，等待operator把Pod拉起来
```

#### 2. 工作节点执行命令

```bash
# 所有工作节点执行

# 步骤4：删除redis数据目录
cd /data/redis_root
rm -rf *
```

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n redis-opt
# redis相关Pod应该重新启动并运行正常
```

---

## 3.17  Bitnami redis-cluster安装（可选）

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 安装
helm install -n redis-opt myredis-cluster \
  --set "password=amarsoft,cluster.nodes=6,image.registry=registry:5000,image.tag=8.0.3,global.security.allowInsecureImages=true,global.storageClass=managed-nfs-storage" \
  /root/redis/redis-cluster/redis-cluster

# 卸载
helm uninstall -n redis-opt myredis-cluster
cd /data/nas_data/
rm -rf $(find redis-opt-redis-data-myredis-cluster-* -name ap* )
rm -f $(find redis-opt-redis-data-myredis-cluster-* -name node* )
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 验证安装结果

```bash
# 在k8sc1控制节点上执行

kubectl get pod -n redis-opt
# redis-cluster相关Pod状态应为Running
```

---

## 3.18  配置redis监控

#### 1. 控制节点执行命令

```bash
# 仅在k8sc1控制节点上执行

# 1. 安装redis-exporter
kubectl apply -f /data/k8s_install/03.setup_file/allyaml/redis/allyaml/exporter/redis-exporter-all.yml
```

#### 2. 工作节点执行命令

无需执行。

#### 3. 镜像仓库执行命令

无需执行。

#### 4. 配置prometheus（在kubemate界面操作）

```bash
# 在kubemate管理界面中操作：

# 1. 进入"集群监控->保密配置"
# 2. 命名空间选择为kubemate-monitoring-system
# 3. 点击编辑按钮，在末尾添加redis-exporter配置：
#    - job_name: redis
#      static_configs:
#        - targets: ["redis-exporter:9121"]

# 4. 进入"系统管理->应用中间件配置"
# 5. 添加redis监控页面
# 6. 地址填写：client:///middleware/redis （注意是三个///）

# 7. 重新登录后验证
```

#### 5. 验证安装结果

在kubemate管理界面中验证redis监控页面能正常显示。

---

## 3.19  定时任务

### 3.19.1 ETCD备份

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

### 3.19.2 Traefik清理

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

### 3.19.3 应用日志清理

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
