#!/bin/bash

#===============================================================================
# 脚本名称：34-install-skywalking.sh
# 功能：安装skywalking
# 执行机器：k8sc1控制节点执行
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================

echo "【INFO】: 开始安装Skywalking..."

# 1. 获取Elasticsearch密码（保存到本地）
kubectl get -n kubemate-system secret es-skywalking-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'

# 2. 修改skywalking配置文件
cd /data/k8s_install/03.setup_file/allyaml
vi 3.skywalking-es.yml
# 修改第74-76行，将ES_PASSWORD替换为步骤1获取的密码

# 3. 安装skywalking
kubectl delete -f 3.skywalking-es.yml
kubectl apply -f 3.skywalking-es.yml

echo "【INFO】: Skywalking安装完成"

# 验证安装结果
# 在k8sc1控制节点上执行

kubectl get pod -n kubemate-system | grep skywalking
# skywalking相关Pod状态应为Running（skywalking-oap启动较慢，需要多等一会儿）
