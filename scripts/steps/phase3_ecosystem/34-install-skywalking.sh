#!/bin/bash

#===============================================================================
# 脚本名称：34-install-skywalking.sh
# 功能：安装skywalking
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

# PROJECT_ROOT 由 main.sh export，无需推算

# 加载公共函数库
source "${PROJECT_ROOT}/scripts/lib/logger.sh"
source "${PROJECT_ROOT}/scripts/lib/config.sh"

log_info "开始安装Skywalking..."

# 获取 K8S 安装目录
K8S_SOFT=$(get_k8s_soft)

# 1. 获取Elasticsearch密码（保存到本地）
kubectl get -n kubemate-system secret es-skywalking-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'

# 2. 修改skywalking配置文件
cd "${K8S_SOFT}/03.setup_file/allyaml"
vi 3.skywalking-es.yml
# 修改第74-76行，将ES_PASSWORD替换为步骤1获取的密码

# 3. 安装skywalking
kubectl delete -f 3.skywalking-es.yml
kubectl apply -f 3.skywalking-es.yml

log_info "Skywalking安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep skywalking
# skywalking相关Pod状态应为Running（skywalking-oap启动较慢，需要多等一会儿）
