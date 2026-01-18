![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image002.png)

| 安硕KUBEMATE |
| ------------ |
| 部署手册     |

 

 

 

 

 

 

-**受控文件**-

 

 

 

 

 

![文本框: 2024年11月  ](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image003.png)![文本框: 上海安硕信息技术股份有限公司](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image004.png)



# 1    前言

KUBEMATE是上海安硕信息技术股份有限公司自主研发的K8S运维管理平台。该平台提供了集群监控、应用发布、容器管理、配置中心、网关等功能。

 该平台依赖与K8S，本文主要介绍K8S集群搭建，和KUBEMATE管理软件的部署。



 

# 2     K8S底座安装

## 2.1     安装要求

### 2.1.1 服务器规划

本次安装涉及到的服务器有3台管理节点、6台工作节点，镜像仓库放在k8sc1，具体分配如下：



| **名称**              | **主机名**           | **IP**     |
| --------------------- | -------------------- | ---------- |
| K8S管理节点           | k8sc1                | 10.3.66.18 |
| K8S管理节点           | k8sc2                | 10.3.66.19 |
| K8S管理节点(镜像仓库) | k8sc3（dockerimage） | 10.3.66.20 |
| K8S工作节点1          | k8sw1                | 10.3.66.21 |
| K8S工作节点2          | k8sw2                | 10.3.66.22 |
| K8S工作节点3          | k8sw3                | 10.3.66.23 |
| K8S工作节点4          | k8sw4                | 10.3.66.24 |
| K8S工作节点5          | k8sw5                | 10.3.66.25 |
| K8S工作节点6          | k8sw6                | 10.3.66.26 |

### 2.1.2 服务器目录规划

使用root创建/data文件夹，所有的安装文件、脚本及部署平台的工作路径，都固定在这个路径下

/data文件夹目录层级规划



| **节点**            | **路径**             | **作用**  |
| ------------------- | -------------------- | --------- |
| 控制节点            | /data/k8s_install    | K8S安装包 |
| /data/docker_root   | docker工作路径       |           |
| /data/etcd_root     | etcd存储路径         |           |
| /data/nas_data      | 共享存储路径         |           |
| 工作节点            | /data/k8s_install    | K8S安装包 |
| /data/docker_root   | docker工作路径       |           |
| /data/log_root      | 应用程序日志存放路径 |           |
| /data/redis_root    | 应用程序日志存放路径 |           |
| 镜像仓库            | /data/k8s_install    | K8S安装包 |
| /data/docker_root   | docker工作路径       |           |
| /data/registry_data | 镜像仓库文件路径     |           |

 

### 2.1.3 全部以root用户进行安装

默认使用具有sudo权限的用户，使用sudo命令切换到root用户下

sudo su -

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image005.png)

 



## 2.2     安装前准备（执行机器：k8s控制节点 + k8s工作节点 + 镜像仓库）



### 2.2.1 上传安装文件(注意，是01.k8s_install目录)

上传至/data路径下：

 

| **服务器**  | **上传包**                                                   |
| ----------- | ------------------------------------------------------------ |
| K8S控制节点 | 01.rpm_package、02.install_package、03.setup_file、05.crontab |
| K8S工作节点 | 01.rpm_package、02.install_package、05.crontab               |
| 镜像仓库    | 02.install_package、04.registry                              |

### 2.2.2 创建工作目录

所有安装文件，安装路径均放在/data路径下

--切换普通用户创建

mkdir -p /data/k8s_install

scp -r /home/appuser/0* /data/k8s_install

 

### 2.2.3 各服务器文件准备

1.控制节点服务器：

cd /data/k8s_install

tar -zxvf 01.rpm_package.tgz

tar -zxvf 02.install_package.tgz

\#unzip 03.setup_file.zip

tar -zxvf 03.setup_file.tgz

tar -zxvf 05.script.tgz

2. 工作节点服务器

cd /data/k8s_install

tar -zxvf 01.rpm_package.tgz

tar -zxvf 02.install_package.tgz

tar -zxvf 05.script.tgz

 

3. 镜像节点服务器

cd /data/k8s_install

tar -zxvf 02.install_package.tgz

tar -xvf 04.registry.tgz

tar -zxvf 05.script.tgz

 

## 2.3     环境配置

### 2.3.1 修改网络配置

#### 2.3.1.1  修改DNS

该脚本功能，包括关闭swap、关闭防火墙、卸载系统自带容器、配置系统参数等。

1. 查看网卡中的GATEWAY地址，网卡路径：

cat /etc/sysconfig/network-scripts/ifcfg-ens192

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image006.png)

 

2. 修改DNS为GATEWAY地址

vi /etc/systemd/resolved.conf

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image008.jpg)

#### 2.3.1.2  修改IPV6配置

vi /etc/sysconfig/network-scripts/ifcfg-ens192

添加如下配置：

\# IPv6 配置

IPV6INIT=yes

IPV6_AUTOCONF=no

IPV6ADDR=fd00:42::171

IPV6_DEFAULTGW=fd00::1

IPV6_DEFROUTE=yes

IPV6_FAILURE_FATAL=no

IPV6_ADDR_GEN_MODE=none

 

重启网络

systemctl daemon-reload

systemctl restart systemd-resolved

systemctl enable systemd-resolved

systemctl restart NetworkManager

 

验证

ip a

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image010.jpg)

如果重启网络ipv6数值没有变化，直接重启服务器。



### 2.3.2 修改主机名

1.修改hostname

分别登录master和work节点，修改相应主机名

 

  k8sc1为第一个控制节点  k8sc2为第二个控制节点  k8sw1为第一个工作节点  k8sw2为第二个工作节点  …以此类推  

 

hostnamectl set-hostname k8sc1

hostnamectl set-hostname k8sc2

hostnamectl set-hostname k8sc3

hostnamectl set-hostname k8sw1

hostnamectl set-hostname k8sw2

hostnamectl set-hostname k8sw3

hostnamectl set-hostname k8sw4

hostnamectl set-hostname k8sw5

hostnamectl set-hostname k8sw6

\#hostnamectl set-hostname registry

 

验证：

su - root

2.修改/etc/hosts:

master、work、registry所有节点上，执行命令：

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

验证：

cat /etc/hosts

如上图所示，配置成功。如果执行了多遍，删除重复内容。

### 2.3.3 修改open files参数（所有服务器执行）

vi /etc/security/limits.conf

加入:

\* soft nofile 65535

\* hard nofile 65535



 ### 2.3.4 配置环境变量

参数解析

$1: 工作目录路径

$2: IPv6地址（可选）

DUAL_STACK="$1"
IPV6_ADDR="$2"

关闭swap

swapoff -a
if cat /proc/swaps | wc -l | grep -q "1"; then
    echo "【SUCCESS】：swap已经关闭"
else
    echo "【ERROR】：swap仍为开启状态，请检查swapoff是否执行！！！"
fi

sed -i '/swap/d' /etc/fstab
if [ -z $(cat /etc/fstab | grep swap) ]; then
    echo "【SUCCESS】：系统启动不自动挂载swap区"
else
    echo "【ERROR】：文件系统仍有挂载swap区的内容，请检查/etc/fstab！！！"
fi

关闭防火墙

systemctl stop firewalld > /dev/null 2>&1
if systemctl status firewalld | grep Active | grep inactive | wc -l | grep -q "1"; then
    echo "【SUCCESS】：防火墙已经关闭"
else
    echo "【ERROR】：防火墙仍为开启状态，请检查防火墙！！！"
fi

取消防火墙自启动

systemctl disable firewalld > /dev/null 2>&1
if systemctl status firewalld | grep disabled | wc -l | grep -q "1"; then
    echo "【SUCCESS】：防火墙已经关闭自启动"
else
    echo "【ERROR】：防火墙仍为自启动状态，请检查防火墙！！！"
fi

卸载podman等容器

if rpm -qa | grep podman | wc -l | grep -q "0"; then
    echo "【SUCCESS】：系统中不存在podman容器"
else
    yum remove podman -y > /dev/null
    if rpm -qa | grep podman | wc -l | grep -q "0"; then
        echo "【SUCCESS】：系统中存在podman容器，已删除"
    else
        echo "【ERROR】：系统中存在podman容器，请手动删除！！！"
    fi
fi

if rpm -qa | grep containerd | wc -l | grep -q "0"; then
    echo "【SUCCESS】：系统中不存在containerd容器"
else
    yum remove containerd -y
    if rpm -qa | grep containerd | wc -l | grep -q "0"; then
        echo "【SUCCESS】：系统中存在containerd容器，已删除"
    else
        echo "【ERROR】：系统中存在containerd容器，请手动删除！！！"
    fi
fi


sed -i '/nameserver/d' /etc/resolv.conf
echo "8.8.8.8 nameserver" >> /etc/resolv.conf

转发ipv4 ipv6并让iptables看到桥接流量

cat << EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

if ls /etc/modules-load.d/k8s.conf | wc -l | grep -q "1" ; then
    echo "【SUCCESS】：转发ipv4并让iptables看到桥接流量"
else
    echo "【ERROR】：转发ipv4并让iptables看到桥接流量"
fi

修改sysctl.conf

sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-iptables/d' /etc/sysctl.conf
sed -i '/net.bridge.bridge-nf-call-ip6tables/d' /etc/sysctl.conf
echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf

ipv6

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


sysctl --system > /dev/null

if lsmod | grep -q br_netfilter; then
    echo "【SUCCESS】：br_netfilter配置成功"
else
    echo "【ERROR】：br_netfilter配置失败"
    exit 1
fi

if lsmod | grep -q overlay; then
    echo "【SUCCESS】：overlay配置成功"
else
    echo "【ERROR】：overlay配置失败"
    exit 1
fi

验证sysctl参数配置

echo "验证系统参数配置..."

params=(
    "net.ipv6.conf.all.disable_ipv6=0"
    "net.ipv6.conf.default.disable_ipv6=0"
    "net.ipv6.conf.lo.disable_ipv6=0"
    "net.ipv6.conf.all.forwarding=1"
    "net.ipv6.conf.default.forwarding=1"
    "net.bridge.bridge-nf-call-iptables=1"
    "net.bridge.bridge-nf-call-ip6tables=1"
    "net.ipv4.ip_forward=1"
)

检查每个参数

all_ok=true
for expected in "${params[@]}"; do
    param="${expected%=*}"
    expected_value="${expected#*=}"
    current_value=$(sysctl -n "$param" 2>/dev/null)

​    if [ $? -eq 0 ]; then
​        if [ "$current_value" = "$expected_value" ]; then
​            echo "【SUCCESS】：$param = $current_value (OK)"
​        else
​            echo "【ERROR】：$param = $current_value (期望: $expected_value)"
​            all_ok=false
​        fi
​    else
​        echo "【ERROR】：$param 参数不存在"
​        all_ok=false
​    fi
done

输出最终结果

if $all_ok; then
    echo "【SUCCESS】：sysctl所有参数检查通过 (OK)"
    exit 0
else
    echo "【ERROR】：sysctl部分参数不符合预期"
    exit 1
fi

systemctl enable systemd-resolved > /dev/null 2>&1
if  systemctl list-unit-files -t service | grep systemd-resolved | awk '{print $NF}' | grep -q "enabled" ; then
    echo "【SUCCESS】： systemd-resolved 自启动"
else
    echo "【ERROR】： systemd-resolved 自启动"
    exit 1
fi

验证IPv6连通性（ping网关）

​    if [ -n "$MAIN_NIC" ]; then
​        gateway_ipv6=$(ip -6 route | grep "default via" | awk '{print $3}' | head -1)
​        if [ -n "$gateway_ipv6" ]; then
​            echo "测试IPv6网关连通性: $gateway_ipv6"
​            if ping6 -c 3 -W 2 "$gateway_ipv6" > /dev/null 2>&1; then
​                echo "【SUCCESS】：IPv6网关连通正常"
​            else
​                echo "【WARNING】：IPv6网关连通失败"
​            fi
​        fi
​    fi

验证系统IPv6参数

​    echo "==================== 系统IPv6参数验证 ===================="
​    sysctl_params=(
​        "net.ipv6.conf.all.disable_ipv6"
​        "net.ipv6.conf.default.disable_ipv6"
​        "net.ipv6.conf.lo.disable_ipv6"
​        "net.ipv6.conf.all.forwarding"
​        "net.ipv6.conf.default.forwarding"
​    )

​    for param in "${sysctl_params[@]}"; do
​        value=$(sysctl -n "$param" 2>/dev/null)
​        if [ $? -eq 0 ]; then
​            echo "  $param = $value"
​        else
​            echo "  $param = 未找到"
​        fi
​    done

​    echo "==================== IPv6配置完成 ===================="
​    echo "IPv6配置已完成并验证"
else
​    echo "双栈模式未启用，跳过IPv6相关验证"
fi

执行结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image012.jpg)

如图所示，无ERROR即为执行成功。

## 2.4     安装containerd（执行机器：k8s控制节点 + k8s工作节点 + 镜像仓库）

执行机器：

1. 执行containerd安装脚本

cd /tmp/k8s/02.container_runtime
#解压containerd-1.7.18-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.18-linux-amd64.tar.gz
#创建containerd自启service
cp containerd.service /etc/systemd/system/containerd.service
#安装runc
install -m 755 runcv1.3.3.amd64 /usr/local/sbin/runc
#安装cni-plugins
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.8.0.tgz
#生成默认配置文件
mkdir -p /etc/containerd
cp config-1.7.18.toml /etc/containerd/config.toml
#安装buildkit
tar Cxzvf /usr/local buildkit-v0.25.2.linux-amd64.tar.gz
#创建buildkit自启服务并启动
cp buildkit.s* /etc/systemd/system/
systemctl daemon-reload
systemctl enable buildkit.service --now
#安装nerdctl
tar -zxf nerdctl-2.2.0-linux-amd64.tar.gz
chmod +x nerdctl
mv nerdctl /usr/local/bin/
#修改nerdctl0地址   使用jq修改 gateway  subnet

配置镜像仓库地址

mkdir -p /etc/containerd/certs.d/$registry:5000
cat > /etc/containerd/certs.d/$registry:5000/hosts.toml <<EOF
server = "http://$registry:5000"

[host."http://$registry:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

配置镜像仓库地址域名

mkdir -p /etc/containerd/certs.d/registry:5000
cat > /etc/containerd/certs.d/registry:5000/hosts.toml <<EOF
server = "http://registry:5000"

[host."http://registry:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

systemctl daemon-reload
systemctl enable --now containerd

验证containerd安装和启动状态

echo "验证containerd安装状态..."

检查containerd服务状态

if systemctl is-active --quiet containerd; then
    echo "✓ containerd服务运行正常"
else
    echo "✗ containerd服务未运行"
    exit 1
fi

检查containerd服务是否已启用

if systemctl is-enabled --quiet containerd; then
    echo "✓ containerd服务已设置为开机自启"
else
    echo "✗ containerd服务未设置为开机自启"
fi

检查containerd版本

containerd_version=$(containerd --version)
echo "✓ containerd版本: $containerd_version"

检查runc版本

runc_version=$(runc --version)
echo "✓ runc版本: $runc_version"

检查nerdctl版本

nerdctl_version=$(nerdctl version)
echo "✓ nerdctl版本: $nerdctl_version"

检查CNI插件

if [ -d "/opt/cni/bin" ] && [ "$(ls -A /opt/cni/bin)" ]; then
    echo "✓ CNI插件已安装"
else
    echo "✗ CNI插件安装失败"
    exit 1
fi

检查buildkit服务状态

if systemctl is-active --quiet buildkit; then
    echo "✓ buildkit服务运行正常"
else
    echo "✗ buildkit服务未运行"
    exit 1
fi

检查containerd配置文件

if [ -f "/etc/containerd/config.toml" ]; then
    echo "✓ containerd配置文件已创建"
else
    echo "✗ containerd配置文件不存在"
    exit 1
fi

检查镜像仓库配置

if [ -d "/etc/containerd/certs.d/$registry:5000" ] && [ -f "/etc/containerd/certs.d/$registry:5000/hosts.toml" ]; then
    echo "✓ 镜像仓库配置已创建"
else
    echo "✗ 镜像仓库配置失败"
    exit 1
fi

echo "containerd安装验证完成"

 

2. 验证

ctr -v

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image013.png)

 

出现此图即为安装成功

 

 

## 2.5     装镜像仓库(安装机器：仅镜像仓库服务器安装)

**镜像仓库，根据自身需要，三选一即可**

### 2.5.1 安装registry免密

1. 安装docker

执行docker安装脚本

sh /data/k8s_install/02.install_package/docker_install.sh 10.3.66.20

\## 10.3.66.20 参数为镜像仓库地址

出现此图即为安装成功

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image015.jpg)

 

2. 执行安装镜像仓库脚本

· 第一个参数为镜像仓库的IP地址

sh /data/k8s_install/04.registry/registry_install.sh 192.168.66.20

执行成功如下图所示：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image017.jpg)

2. 验证

打开浏览地址：http://10.3.66.20:5080

 

### 2.5.2 安装registry加密

1. 执行脚本

· 第一个参数为镜像仓库的IP地址

· 第二个参数是镜像仓库的用户名

· 第三个参数是镜像仓库的密码

sh /data/k8s_install/04.registry/registry_install.sh 192.168.66.20 amarsoft amarsoft@123456

执行成功如下图所示：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image017.jpg)

1. 验证

打开浏览地址：http://10.3.66.20:5080

### 2.5.3 安装harbor

#### 2.5.3.1  配置https证书

如果没有要求，不需要使用https，忽略该章节即可，并将配置文件中的https配置注释掉。

1. 生成 CA 证书私钥。

openssl genrsa -out ca.key 4096

2.生成 CA 证书。

**调整 -subj** **选项中的值以反映您的组织。如果您使用 FQDN** **连接您的 Harbor** **主机，则必须将其指定为公用名 (CN)** **属性。**

openssl req -x509 -new -nodes -sha512 -days 3650 \

 -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=MyPersonal Root CA" \

 -key ca.key \

 -out ca.crt

3.生成服务器证书

**证书通常包含一个.crt** **文件和一个.key** **文件，例如，yourdomain.com.crt** **和 yourdomain.com.key****。**

**生成私钥。**

openssl genrsa -out yourdomain.com.key 4096

**生成证书签名请求 (CSR)****。**

**调整 -subj** **选项中的值以反映您的组织。如果您使用 FQDN** **连接您的 Harbor** **主机，则必须将其指定为公用名 (CN)** **属性，并在密钥和 CSR** **文件名中使用它。**

openssl req -sha512 -new \

  -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=10.1.11.24" \

  -key yourdomain.com.key \

  -out yourdomain.com.csr

**生成 x509 v3** **扩展文件。**

**无论您是使用 FQDN** **还是 IP** **地址连接到您的 Harbor** **主机，您都必须创建此文件，以便您可以为您的 Harbor** **主机生成符合主题备用名称 (SAN)** **和 x509 v3** **扩展要求的证书。替换 DNS** **条目以反映您的域。**

cat > v3.ext <<-EOF

authorityKeyIdentifier=keyid,issuer

basicConstraints=CA:FALSE

keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment

extendedKeyUsage = serverAuth

subjectAltName = @alt_names

 

[alt_names]

DNS.1=yourdomain.com

DNS.2=yourdomain

DNS.3=hostname

IP.1=10.1.11.24

EOF

**使用 v3.ext** **文件为您的 Harbor** **主机生成证书。**

**将 CSR** **和 CRT** **文件名中的 yourdomain.com** **替换为 Harbor** **主机名。**

openssl x509 -req -sha512 -days 3650 \

  -extfile v3.ext \

  -CA ca.crt -CAkey ca.key -CAcreateserial \

  -in yourdomain.com.csr \

  -out yourdomain.com.crt

4.将证书提供给 Harbor 和 Docker

生成 ca.crt、yourdomain.com.crt 和 yourdomain.com.key 文件后，您必须将它们提供给 Harbor 和 Docker，并重新配置 Harbor 以使用它们。

将服务器证书和密钥复制到 Harbor 主机上的证书文件夹中。

cp yourdomain.com.crt /data/harbor/cert/

cp yourdomain.com.key /data/harbor/cert/

将 yourdomain.com.crt 转换为 yourdomain.com.cert，供 Docker 使用。

Docker 守护程序将 .crt 文件解释为 CA 证书，将 .cert 文件解释为客户端证书。

openssl x509 -inform PEM -in yourdomain.com.crt -out yourdomain.com.cert

将服务器证书、密钥和 CA 文件复制到 Harbor 主机上的 Docker 证书文件夹中。您必须先创建相应的文件夹。

cp yourdomain.com.cert /etc/docker/certs.d/yourdomain.com/

cp yourdomain.com.key /etc/docker/certs.d/yourdomain.com/

cp ca.crt /etc/docker/certs.d/yourdomain.com/

如果您将默认 nginx 端口 443 映射到其他端口，请创建文件夹 /etc/docker/certs.d/yourdomain.com:port 或 /etc/docker/certs.d/harbor_IP:port。

重新启动 Docker 引擎。

systemctl restart docker

#### 2.5.3.2  安装docker-compose

[Release v2.35.0 · docker/compose · GitHub](https://github.com/docker/compose/releases/tag/v2.35.0)

 

chmox +x docker-compose-linux-x86_64

cp docker-compose-linux-x86_64 /usr/local/bin/docker-compose

#### 2.5.3.3  启动harbor

1. 上传文件，读取镜像

tar -zxf harbor-offline-installer-v2.13.0.tgz

cd harbor

doker load -i harbor.v2.13.0.tar.gz

2. 上传修改harbor.yml，修改并创建对应目录路径

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image019.jpg)

不配置https，https相关配置可以注释掉

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image021.jpg)

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image023.jpg)

 

 

3. 执行prepare.sh

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image025.jpg) 

4. 执行install.sh

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image027.jpg)

 

启动harbor

docker-compose up -d

 

查看docker进程状态，状态都为Healthy即可

docker-compose ps

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image029.jpg)

 

## 2.6     安装kubernetes

### 2.6.1 安装依赖包(安装机器：所有K8S控制节点和K8S工作节点)

1）master和worker都要安装依赖，下同。

cd /data/k8s_install/01.rpm_package/kubernetes-1.30.14

rpm -ivh *.rpm

 

出现下图即为安装成功。![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image031.jpg)

2）kubeadm替换【可选】，可支持100年不换，否则每年需要更新一次：

备份并替换：

cd /data/k8s_install/01.rpm_package/kubernetes
 chmod +x kubeadm-1.30.14-100y-amd 
 cp /usr/bin/kubeadm /data/k8s_install/01.rpm_package/kubeadm_bak

cd /data/k8s_install/01.rpm_package/ 
 scp kubeadm-1.30.14-100y-amd /usr/bin/kubeadm

执行结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image032.png)

3）kubelet默认启动

执行命令：

systemctl enable kubelet.service

出现下图即为执行成功：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image034.jpg)

### 2.6.2 初始化K8S集群

 

**1.** **安装机器：****仅在****master1****控制节点****上安装**

1) 设置集群初始化文件(注意红色部分需要修改成本地的ip地址等相关信息)

cd /data/k8s_install/03.setup_file

vi cluster.yaml

修改IP为本机IP

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image036.jpg)

2) 配置kubelet路径，

echo KUBELET_EXTRA_ARGS=\'--root-dir=/data/kubelet_root\' > /etc/sysconfig/kubelet

 

3) 初始化并启动集群
4) 执行命令：

cd /data/k8s_install/03.setup_file

kubeadm init --upload-certs --config cluster.yaml

出现如下信息，说明执行成功

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image038.jpg)
   【如果报错则根据提示解决后，全部执行sudo kubeadm reset,然后重新执行kubeadm init --upload-certs --config cluster.yaml】

2. 执行下面命令

mkdir -p $HOME/.kube

sudo scp  /etc/kubernetes/admin.conf $HOME/.kube/config

sudo chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=/etc/kubernetes/admin.conf

 

3. 复制kubeadm join的命令到本地，供2.5.3章节使用（将工作节点加入到master节点）

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image040.jpg)

4. **将上述红框密钥复制到本地notepad****上，暂不执行，如未复制密钥，先执行kubeadm reset****，然后从2.5.2****的第三小步步骤开始执行。**
5. 验证

kubectl get nodes
 kubectl get pods -A

执行正确结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image042.jpg)
   备注：NotReady暂时正常需装完cni插件，status才会变为Ready。coredns显示为Pending也是同样的原因。

 

### 2.6.3 修改证书有效期

1. 修改证书

初始化完成后，需要修改kube-controller-manager的参数，保证工作节点获取的证书也是一百年，如下：

执行：

vi /etc/kubernetes/manifests/kube-controller-manager.yaml

 

在spec.contrainers.command下面最后一行添加：

\- --cluster-signing-duration=867240h0m0s

截图如下：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image044.jpg)

 

2. 验证证书

kubeadm certs check-expiration

执行结果为正确结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image046.jpg)

 

### 2.6.4 添加K8S控制节点（搭建高可用时执行，单master节点部署可跳过该步骤）

**执行节点：只需要另外两台k8s****控制节点执行（一台执行完了，再执行另一台）**

根据2.5.2章节，安装完k8s master后的提示，复制kubeadm join的命令，在剩余master节点执行该命令，将K8S所有master节点加入master集群中，截图如下：

kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \

​    --discovery-token-ca-cert-hash sha256:be3037375048669762a18c0d820994613d4611c768f524fca5d808ca3caf47da \

​    --control-plane --certificate-key 8cc3bc5f73f00cfb37c77413a73c87513dad3142ab3c5052a124387efc8b8742

 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image048.jpg)

 

三台控制节点执行(**执行完该部分和上面两串字符才能验证，即master****和node****执行加入后，master****再执行该部分，最后验证**)：

mkdir -p $HOME/.kube

sudo scp  /etc/kubernetes/admin.conf $HOME/.kube/config

sudo chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=/etc/kubernetes/admin.conf

验证，出现三台master即可：

kubectl get nodes

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image049.png)

### 2.6.5 添加K8S工作节点

**执行节点：****仅在****worker****上执行**

根据2.5.2章节，安装完k8s master后的提示，复制第二条kubeadm join的命令，在所有工作节点执行该命令，将K8S所有工作节点加入master节点中，截图如下：

kubeadm join k8sc1:6443 --token abcdef.0123456789abcdef \

​    --discovery-token-ca-cert-hash sha256:abb882fd3462e84cd1c1f9ecf39ca305f6acb8bd8f2ffb72ccf3cba3341df05e

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image051.jpg)

执行成功截图如下：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image053.jpg)

**在master****任一控制节点上验证：**

kubectl get nodes

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image055.jpg)

如图所示，即为执行成功，NotReady是因为缺少flannel插件，插件在下个章节安装。

**注：当失败后，执行下面命令：**

如果出现Unable to connect to the server: x509的错误，是重置k8s-master，节点证书配置的问题。需要重新执行如下命令。

mkdir -p $HOME/.kube

sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

sudo chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=/etc/kubernetes/admin.conf

 

### 2.6.6 安装cni插件-flannel（仅在master1上安装）

1. 查看yaml中的网络配置，是否和cluster.yaml中的网段是否一致

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image057.jpg)

2. 安装:

kubectl apply -f /data/k8s_install/03.setup_file/kube-flannel.yml

执行结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image058.png)

3. 验证:

kubectl get nodes
 kubectl get pods -A

 

执行正确结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image060.jpg)

注意：

1. 第一条命令“kubectl get nodes”的status为Ready即为成功
2. 第二条命令，“kubectl get pods --all-namespaces”的status为Running表示成功。

 

如果没有生效（READY显示为0/1），可以通过脚本:kubectl describe kube-flannel-ds-xxxx -n kube-flannel查看出错信息。

# 3    kubemate安装

## 3.1     操作机器说明

**所有操作，如无特殊说明，只要在master1节点上操作即可。**

目前需要切换到root用户：执行命令sudo su –

 

### 3.1.1 创建命名空间

kubectl apply -f /data/k8s_install/03.setup_file/allyaml/0.kubemate-namespace.yaml

 

### 3.1.2 安装kubemate管理界面（仅在master1节点安装）

1) **修改1.kubemate.yml:**

 

cd /data/k8s_install/03.setup_file/allyaml

vi 1.kubemate.yml

 

730行改成master1的IP

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image062.jpg)

**3****）安装**

kubectl apply -f 1.kubemate.yml

kubectl apply -f 1.kubemate.yml

 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image064.jpg)

** 如果出现no matches错误，再次执行当前命令即可。

如图所示即为成功。

**４）验证：**

等待一下，访问http://10.3.66.18:30088

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image066.jpg)

 

用户名密码：admin/000000als

 

 

 

### 3.1.3 创建全局镜像仓库

再保密配置中，添加“全局镜像仓库”，录入地址及用户名密码。

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image068.jpg)

### 3.1.4 安装nfs插件

**1）****验证系统是否自带****nfs**

systemctl status nfs-server

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image070.jpg)

**如果存在****nfs-server****，则跳过步骤****2****。**

 

**2）****安装****nfs****（在****master****三个节点、所有****work****节点安装****）：**

 

执行命令：

cd /data/k8s_install/01.rpm_package/nfs

rpm -ivh *.rpm

如下图所示，执行成功。

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image072.jpg)

**3）****nfs-server****自启动****(****所有节点均需执行****)**

systemctl enable nfs-server && systemctl start nfs-server

 

**4）****挂载****nas/nfs****（所有节点执行，该步骤需要在服务器给付之前要求系统岗挂载好）**

mkdir -p /data/nas_root #一般不执行，验证即可

mount -t nfs **10.3.5.221:/kvmdata/nfsdata/xdnfs** /data/nas_root #一般不执行，验证即可

\#解挂载

\#umount -f /data/nas_root

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image073.png)

挂载配置：/data/nas_root

 

**5）****修改****nfs.yml****配置****(master1****节点****)**

打开nfs-values.yml，

cd /data/k8s_install/03.setup_file/allyaml

vi nfs-value.yaml

修改成nas server提供的IP和访问路径。

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image075.jpg)

 

 

**6）****修改启动自动挂载参数****(****所有****work****节点执行****)**

vi /etc/fstab #分开执行

\# ip:/nas_root为nas盘路径，10.3.31.11:/kvmdata/nfsdata/k8s_pt

10.3.5.221:/kvmdata/nfsdata/xdnfs /data/nas_root nfs defaults 0 0 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image077.jpg)

**7）****安装****(****仅在****master1****节点执行****)**

cp /data/k8s_install/03.setup_file/allyaml/linux-amd64/helm /usr/local/bin/helm

cd /data/k8s_install/03.setup_file/allyaml

helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/ -f nfs-value.yaml

**8）****验证**

kubectl get pod 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image079.jpg)

状态为running为执行成功。

### 3.1.5 安装elasticsearch(master1节点执行)

**1）****安装**

cd /data/k8s_install/03.setup_file/allyaml

kubectl apply -f 2.es-crds.yml
 kubectl apply -f 2.es-operator.yml
 kubectl apply -f 2.es-skywalking.yml

 

**2）****验证**

kubectl get po -A

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image081.jpg)

图中红线内为running为执行成功。

 

### 3.1.6 安装skywalking（仅在master1节点执行）

 

**1）****获取密码（保存在本地）**

kubectl get -n kubemate-system secret es-skywalking-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'

执行结果

 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image083.jpg)

 

**2）****修改****elasticsearch****连接参数**

打开3.skywalking-es.yml，74-76行改为实际的参数

vi 3.skywalking-es.yml

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image085.jpg)

 

ES_PASSWORD：替换成步骤1获取的密码

 

**3）****安装**

kubectl delete -f 3.skywalking-es.yml

kubectl apply -f 3.skywalking-es.yml

 

**4）****验证**

kubectl get pod -n kubemate-system

 

 ![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image087.jpg)

 

红线中为running为执行成功。

skywalking-oap启动比较慢，多等会儿即可。

 

### 3.1.7 安装loki（master1节点执行）

**1）****创建工作路径**(**把loki****存储保存在本地磁盘，这一步所有worker****执行，若使用共享存储，跳过此步**)

mkdir -p /data/loki_root

chown -R 10001:10001 /data/loki_root

 

**2）****安装**

cd /data/k8s_install/03.setup_file/allyaml

kubectl apply -f 4.loki.yml
 kubectl apply -f 4.loki-sec.yml

 

**3）****验证**

kubectl get pod -n kubemate-system

 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image089.jpg)

红线中均为running，即为正确。

### 3.1.8 安装traefik（仅在master1节点执行）

**1.** **安装（5.traefik.yml****执行两遍）**

cd /data/k8s_install/03.setup_file/allyaml

kubectl apply -f 5.traefki-ds.yaml

kubectl apply -f 5.traefki-ds.yaml
 kubectl apply -f 6.logfmt-manage.yml

 ![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image091.jpg)

 

**2.** **验证**

kubectl get pod -n kubemate-system

 ![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image093.jpg)

红线中为running为执行成功。

### 3.1.9 安装traefik-mesh（仅在master1节点执行）

**1）****安装**

cd /data/k8s_install/03.setup_file/allyaml

kubectl apply -f 5-1.traefik-mesh.yml

 

**2）****验证**

kubectl get pod -n kubemate-system

 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image095.jpg)

红线中为running为执行成功。

 

### 3.1.10     安装prometheus（仅在master1节点执行）

**1****）切换目录**

cd /data/k8s_install/03.setup_file/allyaml/prometheus

**2****）安装**

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

### 3.1.11     更新coredns配置（仅在master1节点执行）

配置反亲和性，防止coredns同时启动在一个worker上。

**1****）执行**

cd /data/k8s_install/03.setup_file/allyaml

kubectl apply -f coredns-update.yml

kubectl rollout restart -n kube-system deployment coredns

sleep 5 #等待coredns重启完毕
 kubectl rollout restart deployment/traefik-mesh-controller -n kubemate-system

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image097.jpg)



执行：

kubectl edit deployment coredns -n kube-system

**在40****行，****spec.template.spec****下添加如下选中的代码**：（格式注意对齐）

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image099.jpg)

\## 按esc后输入:wq保存直接退出。

   affinity: 

​    podAntiAffinity:

​     preferredDuringSchedulingIgnoredDuringExecution:

​     \- weight: 1

​      podAffinityTerm:

​       labelSelector:

​        matchExpressions:

​        \- key: k8s-app

​          operator: In

​         values:

​         \- kube-dns

​       topologyKey: kubernetes.io/hostname

### 3.1.12     安装mertics-server（仅在master1节点执行）

1. 执行安装脚本

sh /data/k8s_install/03.setup_file/mertics-server/mertics-server-install.sh amd64

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image101.jpg)

### 3.1.13     配置普通用户kubectl权限

 

cp -r .kube /home/appusr/

chown -R appusr:appusr .kube/

 

### 3.1.14     配置F5 master高可用

修改/etc/hosts

k8sc1的IP改为当前中心F5的IP

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image103.jpg)



 

### 3.1.15     安装redis哨兵模式

cd /data/k8s_install/03.setup_file/allyaml/redis

kubectl create ns redis-sentinel

kubectl apply -f redis-sentinel/redis-pv.yml

kubectl apply -f redis-sentinel/storageclass.yml

helm install -n redis-sentinel redis-ha allyaml/redis-ha

 

### 3.1.16     安装redis集群

#### 3.1.16.1  创建工作路径（master1执行）

**1）****创建存储卷目录（该语句所有worker****节点执行****）**

**mkdir -p /data/redis_root**

 

#### 3.1.16.2  安装redis集群

1）**新建命名空间**

**kubectl create ns redis-opt**

 

2）**创建存储卷**

**cd /data/k8s_install/03.setup_file/allyaml/redis/redis-pvc**

**kubectl apply -f localstorageclass.yaml**

**kubectl apply -f redis-pv.yml**

 

**3）****创建redis-secret**

**kubectl create secret generic redis-secret -n redis-opt --from-literal=password=Xxkjb_Fxcps_Redis2024**

 

创建完可进入kubemate管理页面-保密配置，查看秘钥，并且可以修改秘钥

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image105.jpg)

**4）****安装redis-operator**

**/data/k8s_install/06.redis-cluster/linux-amd64/helm install -n redis-opt redis-operator /data/k8s_install/06.redis-cluster/allyaml/redis-operator**

执行结果：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image107.jpg)

执行完成后，可在kubemate的无状态发布中查看redis-operator状态。

 

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image109.jpg)

**5）****安装redis-cluster**

 

**/data/k8s_install/06.redis-cluster/linux-amd64/helm install -n redis-opt redis-cluster /data/k8s_install/06.redis-cluster/allyaml/redis-cluster**

 

**执行结果：**

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image111.jpg)

 

执行后，可进入kubemate-有状态发布，查看leader和follwer状态。

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image113.jpg)

 

**6）****应用配置(****需要导入als91c.zip)**

进入常规配置中，找到redis-conf，修改为集群模式

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image115.jpg) 

 

#### 3.1.16.3  修改密码

 

**1）**保密配置中的redis-secret中，可以修改redis密码。

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image117.jpg)

**2）****修改密码后，重启redis****，密码就切换成功。(****重启redis****步骤见3.1.14.5)**

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image119.jpg)

**3）****进入redis-cluster-leader****、redis-cluster-follower****的pod****终端中验证密码**

**redis-cli**

**auth xxx**

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image121.jpg)

显示ok，即为修改成功。

 

#### 3.1.16.4  卸载redis集群

在master节点执行

**1）****查看安装详情**

/data/k8s_install/06.redis-cluster/linux-amd64/helm list -A

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image123.jpg)

**2）****卸载redis****集群**

 

/data/k8s_install/06.redis-cluster/linux-amd64/helm uninstall -n redis-opt redis-cluster 

/data/k8s_install/06.redis-cluster/linux-amd64/helm uninstall -n redis-opt redis-operator

 

**3）****删除服务器文件**

rm -rf /data/redis_root/*

 

#### 3.1.16.5  重启Redis

因redis集群是使用operator管理的，需要遵循以下的步骤重启redis集群。否则可能导致redis集群启动失败，程序报no route to host的错误。

 

1. 先将redis-operator的副本数改为0
2. 等步骤1完成后，将redis-leader的副本数改为0
3. 等步骤2 完成后，将redis-follower的副本数改成0.
4. 步骤3完成后，进入/data/redis_root目录，删除目录下所有文件。
5. 将redis-operator的副本数改为1，等待operator把pod拉起来。

 

### 3.1.17     bitnami redis-cluster安装

local-storage可参考上一个章节的内容

\# 安装

helm install -n redis-opt myredis-cluster --set "password=amarsoft,cluster.nodes=6,image.registry=registry:5000,image.tag=8.0.3,global.security.allowInsecureImages=true,global.storageClass=managed-nfs-storage" /root/redis/redis-cluster/redis-cluster

 

\# 卸载

helm uninstall -n redis-opt myredis-cluster

cd /data/nas_data/

rm -rf $(find redis-opt-redis-data-myredis-cluster-* -name ap* )

rm -f $(find redis-opt-redis-data-myredis-cluster-* -name node* )

### 3.1.18     配置redis监控

1. 修改redis-exporter-all.yml连接参数:

47和49行，修改如下图

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image124.png)

 

**2.**     **安装**

kubectl apply -f /data/k8s_install/03.setup_file/allyaml/redis/allyaml/exporter redis-exporter-all.yml

 

**3.**     **配置prometheus**

1. 打开kubemate，点菜单“集群监控->保密配置”,命名空间选择为kubemate-monitoring-system。点下图的编辑按钮：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image126.png)

2. 打开详情，点值区域：

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image128.png)

3. 在末尾添加如下内容（以redis-exporter为例）：

![截屏2023-07-10 21.30.14](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image130.png)

4. 注意：job_name为redis,targets值必须与上述部署的redis-exporter服务一致，服务界面如下图：

![截屏2023-07-10 21.32.29](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image132.png)

5. 点确定并关闭，点保存，即可完成。
6. 进入系统管理，进入应用中间件配置，添加redis监控页面

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image134.jpg)

**地址填写：client:///middleware/redis**  **（注意是三个///****）**

7. 重新登录后验证

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image136.jpg)

 

### 3.1.19     定时任务

#### 3.1.19.1 ETCD备份

主副中心master1上执行etcd备份脚本(**root****权限**)

crontab -e 

10 2 * * * nohup sh /data/k8s_install/05.crontab/etcdbak.sh **1** >> /data/crontab_task/etcdbak/etcdbak.log &

\## 注意etcdbak.sh后面需要带一个参数  1:代表主中心 2:代表副中心

#### 3.1.19.2 Traefik清理

 

主副中心master1上执行traefik日志清理(**root****权限**)

crontab -e 

0 2 * * * nohup sh /data/k8s_install/05.crontab/traefikClear.sh >> /data/k8s_install/05.crontab/traefikClear.log &

#### 3.1.19.3 应用日志清理

主备所有worker上每日执行程序日志备份

crontab -e 

0 2 * * * nohup sh /data/k8s_install/05.crontab /logback.sh >> /data/k8s_install/05.crontab/logback.log &

### 3.1.20     配置response自动添加podname和clustername（该章节有问题，暂不进行配置）

**目前只能显示到traefik****层的podname****，先不安装。**

1. 安装配置文件

cd /data/k8s_install/03.setup_file/allyaml

kubectl apply -f traefik-plugin-podname-response.yaml

kubectl apply -f kubemate-cluster.yaml

 

2. 打开无状态发布（或者在守护进程中）traefik的yaml。添加如下引用

​    \- --experimental.localPlugins.traefik-podname.moduleName=amarsoft.com/traefik/podnameresponseplugin

​    env:

​    \- name: CLUSTERNAME

​     valueFrom:

​      configMapKeyRef:

​        key: name

​       name: kubemate-cluster
 ![截图_选择区域_20241115103719](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image138.jpg)

 

3. 保存，并等待traefik重启完毕
4. 常规配置kubemate-application：添加k8s.name和k8s.traefik.default-middlewares(值为traefik-podname)

![截图_选择区域_20241115104632](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image140.jpg)

 

5. 重启kubemate无状态发布
6. 针对存量的命名空间，还需要打开zip文件中的middleware.yaml，修改namespace，并执行：kubectl apply -f middleware.yaml。【通过kubemate新建命名空间则无需此步骤】
7. 相关的应用路由重新保存（kubemate会自动添加上述的插件）(以下截图以服务网关中的traefik-dashboard路由为例)

![截图_选择区域_20241115105403](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image142.jpg)点明细，再点编辑路由，不用改内容，直接点确定（见下图）。

![截图_选择区域_20241115105505](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image144.jpg) 确定后，自动返回详情界面，可以看到自动添加了网关。   ![截图_选择区域_20241115105729](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image146.jpg)

8. 验证。

 

浏览器输入地址：http://【工作节点IP】:30477/als91c/#/，打开F12。观察response值。结果如下图：
 ![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image148.jpg)



 

# 4    双中心策略

## 4.1     批量执行策略

固定在单中心的某台服务器上。

## 4.2     NAS策略

一个NAS，主副中心均可访问。

## 4.3     F5策略

主中心一个F5、副中心一个F5，主副中心上面总的F5。

![img](file:///C:/Users/pcxiang/AppData/Local/Temp/msohtmlclip1/01/clip_image150.jpg)

 



| **F5**   | **健康检查** | **业务转发端口** | **控制节点** |
| -------- | ------------ | ---------------- | ------------ |
| 主中心F5 | 32477        | 30477            | 6443         |
| 副中心F5 | 32477        | 30477            | 6443         |
| 上层F5   | --           | 30477            | --           |

注：32477对应的是traefik容器内的9000端口