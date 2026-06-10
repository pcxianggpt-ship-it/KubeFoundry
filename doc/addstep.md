
# 安装prometheus

cd /root/k8s-media/03.setup_file/v1.30.14/prometheus
kubectl label node k8sw1 k8sw2 prom=true
kubectl apply -f promlocal-pv.yaml
kubectl apply -f 1-crd
kubectl apply -f 2-prometheusOperator
kubectl apply -f 3-prometheus
kubectl apply -f 4-nodeExporter
kubectl apply -f 5-kubeStateMetrics
kubectl apply -f 6-alertmanager
kubectl apply -f 8-metrics-server-ha.yaml
kubectl apply -f kubernetesControlPlaneRule
kubectl apply -f process-exporter.yaml

# 安装openebs
cd /root/k8s-media/03.setup_file/v1.30.14/helmapp/openebs
mkdir -p /data/openebs-root
kubectl apply -f openebssc.yaml
helm install openebs -n kubemate-system -f openebs-values.yaml ./openebs-4.2.0.tgz


# 安装traefik，3.3版本
cd /root/k8s-media/03.setup_file/v1.30.14/traefik
kubectl apply -f 3.3

# 安装alloy
## 创建cm
cd /root/k8s-media/03.setup_file/v1.30.14/helmapp/alloy
kubectl create cm -n kubemate-system --from-file=congfig.alloy=alloy.config
helm install alloy -n kubemate-system -f alloy-values.yaml ./alloy-1.4.0.tgz

# 安装minio
## 安装minio-operator，修改image字段
kubectl apply -f minio-operator.yaml
## 创建minio实例
## 获取operatro的token
kubectl get secret -n kubemate-system console-sa-secret -o jsonpath=”{.data.token}” | base64 -d
## 页面安装minio


# 安装loki

helm install loki -n kubemate-system -f values.yaml ./loki-5.45.0.tgz