#!/usr/bin/env bash
# Renders the airgap manifest templates into ready-to-apply YAML files.
# Substitutes REPLACE_REGISTRY, REPLACE_IMAGE_TAG, and gVisor URL placeholders.
#
# Usage:
#   ./manifests/airgap-install/render.sh <REGISTRY> <IMAGE_TAG> \
#       [--gvisor-amd64-url=URL] [--gvisor-amd64-sha256=SHA] \
#       [--gvisor-arm64-url=URL] [--gvisor-arm64-sha256=SHA] \
#       [--otel-endpoint=URL]
#
# Example:
#   ./manifests/airgap-install/render.sh \
#       registry.example.com/substrate v0.1.0 \
#       --gvisor-amd64-url=http://storage.example.com/gvisor/runsc-amd64 \
#       --gvisor-amd64-sha256=f18a948bf9c8bbb54eb998549a3a8d719a1c7de2efbe8fdd2ff0ee5fecd06f19 \
#       --gvisor-arm64-url=http://storage.example.com/gvisor/runsc-arm64 \
#       --gvisor-arm64-sha256=62eee121f8c188e347c428acc96f111568ede3be37b906046b6f28bbe2cc40c0

set -o errexit -o nounset -o pipefail

REGISTRY="${1:?Usage: $0 <REGISTRY> <IMAGE_TAG> [options]}"
IMAGE_TAG="${2:?Usage: $0 <REGISTRY> <IMAGE_TAG> [options]}"
shift 2

GVISOR_AMD64_URL="REPLACE_GVISOR_AMD64_URL"
GVISOR_AMD64_SHA256="REPLACE_GVISOR_AMD64_SHA256"
GVISOR_ARM64_URL="REPLACE_GVISOR_ARM64_URL"
GVISOR_ARM64_SHA256="REPLACE_GVISOR_ARM64_SHA256"
OTEL_ENDPOINT="http://opentelemetry-collector.monitoring.svc.cluster.local:4317"

for arg in "$@"; do
  case "${arg}" in
    --gvisor-amd64-url=*)       GVISOR_AMD64_URL="${arg#--gvisor-amd64-url=}" ;;
    --gvisor-amd64-sha256=*)    GVISOR_AMD64_SHA256="${arg#--gvisor-amd64-sha256=}" ;;
    --gvisor-arm64-url=*)       GVISOR_ARM64_URL="${arg#--gvisor-arm64-url=}" ;;
    --gvisor-arm64-sha256=*)    GVISOR_ARM64_SHA256="${arg#--gvisor-arm64-sha256=}" ;;
    --otel-endpoint=*)          OTEL_ENDPOINT="${arg#--otel-endpoint=}" ;;
  esac
done

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${DIR}/rendered"
mkdir -p "${OUT}"

render_file() {
  local src="${DIR}/$1"
  local dst="${OUT}/$1"
  sed \
    -e "s|REPLACE_REGISTRY|${REGISTRY}|g" \
    -e "s|REPLACE_IMAGE_TAG|${IMAGE_TAG}|g" \
    -e "s|REPLACE_GVISOR_AMD64_URL|${GVISOR_AMD64_URL}|g" \
    -e "s|REPLACE_GVISOR_AMD64_SHA256|${GVISOR_AMD64_SHA256}|g" \
    -e "s|REPLACE_GVISOR_ARM64_URL|${GVISOR_ARM64_URL}|g" \
    -e "s|REPLACE_GVISOR_ARM64_SHA256|${GVISOR_ARM64_SHA256}|g" \
    -e "s|REPLACE_OTEL_ENDPOINT|${OTEL_ENDPOINT}|g" \
    "${src}" > "${dst}"
  echo "  rendered: ${dst}"
}

echo "==> Rendering airgap manifests"
echo "    REGISTRY:  ${REGISTRY}"
echo "    IMAGE_TAG: ${IMAGE_TAG}"
echo "    OUTPUT:    ${OUT}/"
echo ""

# Files without placeholders are copied as-is
for f in 00-crds.yaml 01-namespaces.yaml 02-rbac.yaml 03-admission-policy.yaml; do
  cp "${DIR}/${f}" "${OUT}/${f}"
  echo "  copied:   ${OUT}/${f}"
done

# Files with placeholders get substituted
for f in \
  04-sandboxconfig.yaml \
  05-pod-certificate-controller.yaml \
  06-valkey.yaml \
  07-rustfs.yaml \
  08-ate-api-server.yaml \
  09-ate-controller.yaml \
  10-atenet-router.yaml \
  11-atenet-dns.yaml \
  12-atelet.yaml; do
  render_file "${f}"
done

echo ""
echo "==> Done. Apply in order:"
echo ""
echo "  # Step 1: CRDs + namespaces (no images)"
echo "  kubectl apply -f ${OUT}/00-crds.yaml"
echo "  kubectl apply -f ${OUT}/01-namespaces.yaml"
echo "  kubectl apply -f ${OUT}/02-rbac.yaml"
echo "  kubectl apply -f ${OUT}/03-admission-policy.yaml"
echo ""
echo "  # Step 2: SandboxConfig (update gVisor URLs first if not done via --flags)"
echo "  kubectl apply -f ${OUT}/04-sandboxconfig.yaml"
echo ""
echo "  # Step 3: Pod certificate controller (must come before secrets)"
echo "  kubectl apply -f ${OUT}/05-pod-certificate-controller.yaml"
echo "  kubectl rollout status deployment/podcertificate-controller \\"
echo "    -n podcertificate-controller-system --timeout=120s"
echo ""
echo "  # Step 4: Create required secrets and ConfigMaps"
echo "  ./hack/airgap/setup-secrets.sh"
echo ""
echo "  # Step 5: Core system components"
echo "  kubectl apply -f ${OUT}/06-valkey.yaml"
echo "  kubectl apply -f ${OUT}/07-rustfs.yaml"
echo "  kubectl apply -f ${OUT}/08-ate-api-server.yaml"
echo "  kubectl apply -f ${OUT}/09-ate-controller.yaml"
echo "  kubectl apply -f ${OUT}/10-atenet-router.yaml"
echo "  kubectl apply -f ${OUT}/11-atenet-dns.yaml"
echo "  kubectl apply -f ${OUT}/12-atelet.yaml"
