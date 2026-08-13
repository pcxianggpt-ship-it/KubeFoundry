#!/bin/bash
set -o errexit -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "${TMP}"' EXIT
mkdir -p "${TMP}/bin"

cat > "${TMP}/bin/kubectl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${KF_COREDNS_KUBECTL_LOG}"
case "$*" in
  *"get pods -n kube-system -l k8s-app=kube-dns -o jsonpath="*) printf '%b' "${KF_COREDNS_POD_IPS:-}" ;;
  *"get deployment coredns -n kube-system -o jsonpath="*"coredns-anti-affinity"*) printf '%s' "${KF_COREDNS_MARKER}" ;;
  *"get deployment coredns -n kube-system -o go-template="*) printf '%b' "${KF_COREDNS_RULE_ROWS}" ;;
  *"get deployment coredns -n kube-system"*) : ;;
  *"rollout status deployment/coredns"*) : ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "${TMP}/bin/kubectl"
export PATH="${TMP}/bin:${PATH}"
export KUBECTL_BIN=kubectl
export KUBECONFIG_PATH="${TMP}/admin.conf"
export KF_COREDNS_KUBECTL_LOG="${TMP}/kubectl.log"
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "$*" >&2; }
export -f log_info log_success log_warn log_error

printf '%s\n' '{"Network": "10.4.0.0/16"}' > "${TMP}/kube-flannel.yml"
export FLANNEL_FILE="${TMP}/kube-flannel.yml"
export DUAL_STACK=N
export KF_COREDNS_POD_IPS='10.4.0.16\n10.4.0.17\n'
bash "${ROOT}/scripts/steps/phase2_k8s_base/22-install-cni-flannel.sh"
grep -Fq 'rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s' "${KF_COREDNS_KUBECTL_LOG}"
grep -Fq 'rollout restart deployment/coredns -n kube-system' "${KF_COREDNS_KUBECTL_LOG}"

: > "${KF_COREDNS_KUBECTL_LOG}"
export KF_COREDNS_POD_IPS='10.244.0.16\n10.244.1.17\n'
bash "${ROOT}/scripts/steps/phase2_k8s_base/22-install-cni-flannel.sh"
if grep -Fq 'rollout restart deployment/coredns -n kube-system' "${KF_COREDNS_KUBECTL_LOG}"; then
    printf 'FAIL: 正常 Flannel 地址仍触发 CoreDNS 重建\n' >&2
    exit 1
fi

: > "${KF_COREDNS_KUBECTL_LOG}"

export KF_COREDNS_MARKER=v1
export KF_COREDNS_RULE_ROWS='0|kubernetes.io/hostname|k8s-app=In=kube-dns,\n1|topology.kubernetes.io/zone|app=In=other,\n2|kubernetes.io/hostname|k8s-app=In=kube-dns,\n'
bash "${ROOT}/scripts/steps/phase2_k8s_base/23-configure-coredns-affinity.sh"
grep -Fq '"op":"remove","path":"/spec/template/spec/affinity/podAntiAffinity/preferredDuringSchedulingIgnoredDuringExecution/2"' "${KF_COREDNS_KUBECTL_LOG}"
grep -Fq 'annotate deployment coredns -n kube-system kubefoundry.io/coredns-anti-affinity=v2 --overwrite' "${KF_COREDNS_KUBECTL_LOG}"
grep -Fq 'rollout restart deployment/coredns -n kube-system' "${KF_COREDNS_KUBECTL_LOG}"

: > "${KF_COREDNS_KUBECTL_LOG}"
export KF_COREDNS_MARKER=v2
export KF_COREDNS_RULE_ROWS='0|kubernetes.io/hostname|k8s-app=In=kube-dns,\n'
bash "${ROOT}/scripts/steps/phase2_k8s_base/23-configure-coredns-affinity.sh"
if grep -Eq ' patch |annotate |rollout restart' "${KF_COREDNS_KUBECTL_LOG}"; then
    printf 'FAIL: 幂等执行仍修改 CoreDNS Deployment\n' >&2
    exit 1
fi

printf 'phase2 CoreDNS affinity tests passed\n'
