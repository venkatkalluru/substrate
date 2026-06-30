#!/usr/bin/env bash
# Creates the Kubernetes secrets and ConfigMaps required by substrate before
# the core system pods can start.
#
# Run this AFTER:
#   1. kubectl apply -f manifests/airgap-install/00-crds.yaml
#   2. kubectl apply -f manifests/airgap-install/01-namespaces.yaml
#   3. kubectl apply -f manifests/airgap-install/05-pod-certificate-controller.yaml
#   4. Waiting for podcertificate-controller rollout to complete
#   5. Waiting for ClusterTrustBundles to be created by the controller
#
# Usage:
#   ./hack/airgap/setup-secrets.sh [--context=<kubectl-context>]
#
# Prerequisites:
#   - Go 1.26+ (to build kubectl-ate)
#   - kubectl configured for the target cluster
#   - jq and openssl installed

set -o errexit -o nounset -o pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
for arg in "$@"; do
  case "${arg}" in
    --context=*) KUBECTL_CONTEXT="${arg#--context=}" ;;
  esac
done

run_kubectl() {
  kubectl ${KUBECTL_CONTEXT:+--context="${KUBECTL_CONTEXT}"} "$@"
}

run_kubectl_ate() {
  go run ./cmd/kubectl-ate ${KUBECTL_CONTEXT:+--context="${KUBECTL_CONTEXT}"} "$@"
}

echo "==> Building kubectl-ate..."
go build -o bin/kubectl-ate ./cmd/kubectl-ate
echo "    Built: bin/kubectl-ate"

echo ""
echo "==> Waiting for podcertificate-controller to be ready..."
run_kubectl rollout status deployment/podcertificate-controller \
  -n podcertificate-controller-system --timeout=120s

echo ""
echo "==> Waiting for ClusterTrustBundles to be created..."
until run_kubectl get clustertrustbundles podidentity.podcert.ate.dev:identity:primary-bundle \
    >/dev/null 2>&1; do
  echo "    Waiting for podidentity bundle..."
  sleep 2
done
until run_kubectl get clustertrustbundles servicedns.podcert.ate.dev:identity:primary-bundle \
    >/dev/null 2>&1; do
  echo "    Waiting for servicedns bundle..."
  sleep 2
done
echo "    ClusterTrustBundles ready."

echo ""
echo "==> Creating JWT authority pool secret..."
run_kubectl get secret -n acr-substrate session-id-jwt-pool >/dev/null 2>&1 || \
  run_kubectl_ate admin make-jwt-pool \
    --key-id="1" \
    --name="session-id-jwt-pool" \
    --secret-namespace=acr-substrate

echo ""
echo "==> Creating session ID CA pool secret..."
run_kubectl get secret -n acr-substrate session-id-ca-pool >/dev/null 2>&1 || \
  run_kubectl_ate admin make-ca-pool \
    --ca-id="1" \
    --name="session-id-ca-pool" \
    --secret-namespace=acr-substrate

echo ""
echo "==> Creating podcertificate controller CA pools..."
run_kubectl create namespace podcertificate-controller-system \
    --dry-run=client -o yaml | run_kubectl apply -f -

run_kubectl get secret -n podcertificate-controller-system service-dns-ca-pool \
    >/dev/null 2>&1 || \
  run_kubectl_ate admin make-ca-pool \
    --ca-id="1" \
    --name="service-dns-ca-pool" \
    --secret-namespace=podcertificate-controller-system

run_kubectl get secret -n podcertificate-controller-system pod-identity-ca-pool \
    >/dev/null 2>&1 || \
  run_kubectl_ate admin make-ca-pool \
    --ca-id="1" \
    --name="pod-identity-ca-pool" \
    --secret-namespace=podcertificate-controller-system

echo ""
echo "==> Creating Valkey CA certs secret..."
if ! run_kubectl get secret -n acr-substrate valkey-ca-certs >/dev/null 2>&1; then
  pool_json=$(run_kubectl get secret -n podcertificate-controller-system service-dns-ca-pool \
    -o jsonpath='{.data.pool}' | base64 --decode)
  der_base64=$(echo "${pool_json}" | grep -o '"RootCertificateDER":"[^"]*' | \
    sed 's/"RootCertificateDER":"//')
  ca_certs=$(echo "${der_base64}" | base64 --decode | openssl x509 -inform der -outform pem)

  run_kubectl create secret generic valkey-ca-certs \
    --from-literal=ca.crt="${ca_certs}" \
    -n acr-substrate \
    --dry-run=client -o yaml \
    | run_kubectl apply -f -
fi

echo ""
echo "==> Creating ate-api-server-envvars ConfigMap..."
if ! run_kubectl get configmap -n acr-substrate ate-api-server-envvars >/dev/null 2>&1; then
  jwt_issuer=$(run_kubectl get --raw /.well-known/openid-configuration 2>/dev/null \
    | grep -o '"issuer":"[^"]*' | sed 's/"issuer":"//' || true)
  if [[ -z "${jwt_issuer}" ]]; then
    jwt_issuer="https://kubernetes.default.svc"
  fi

  run_kubectl create configmap -n acr-substrate ate-api-server-envvars \
    --from-literal=ATE_API_REDIS_ADDRESS="valkey-cluster.acr-substrate.svc:6379" \
    --from-literal=ATE_API_REDIS_USE_IAM_AUTH="false" \
    --from-literal=ATE_API_REDIS_TLS_SERVER_NAME="valkey-cluster.acr-substrate.svc" \
    --from-literal=ATE_API_REDIS_CLIENT_CERT="/run/servicedns.podcert.ate.dev/credential-bundle.pem" \
    --from-literal=ATE_API_K8SJWT_ISSUER="${jwt_issuer}" \
    --dry-run=client -o yaml \
    | run_kubectl apply -f -
fi

echo ""
echo "==> All secrets and ConfigMaps created."
echo ""
echo "Next steps:"
echo "  kubectl apply -f manifests/airgap-install/rendered/06-valkey.yaml"
echo "  kubectl apply -f manifests/airgap-install/rendered/07-rustfs.yaml"
echo "  kubectl apply -f manifests/airgap-install/rendered/08-ate-api-server.yaml"
echo "  kubectl apply -f manifests/airgap-install/rendered/09-ate-controller.yaml"
echo "  kubectl apply -f manifests/airgap-install/rendered/10-atenet-router.yaml"
echo "  kubectl apply -f manifests/airgap-install/rendered/11-atenet-dns.yaml"
echo "  kubectl apply -f manifests/airgap-install/rendered/12-atelet.yaml"
