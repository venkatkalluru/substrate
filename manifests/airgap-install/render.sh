#!/usr/bin/env bash
# Renders the airgap manifest templates into ready-to-apply YAML files.
# Substitutes REPLACE_REGISTRY, REPLACE_IMAGE_TAG, and optional gVisor placeholders.
#
# Usage:
#   ./manifests/airgap-install/render.sh <REGISTRY> <IMAGE_TAG> [OPTIONS]
#
# Options:
#   --gvisor-amd64-url=URL    URL to internal runsc binary (amd64)
#   --gvisor-amd64-sha256=SHA sha256 of the amd64 runsc binary
#   --gvisor-arm64-url=URL    URL to internal runsc binary (arm64)
#   --gvisor-arm64-sha256=SHA sha256 of the arm64 runsc binary
#   --otel-endpoint=URL       OTLP collector address (default: local placeholder)
#   --with-gvisor             Also render 04-sandboxconfig.yaml (only if gVisor is
#                             enabled on cluster nodes; omit for runc/regular containers)
#
# Example — runc/regular containers (no gVisor):
#   ./manifests/airgap-install/render.sh registry.example.com/substrate v0.1.0
#
# Example — with gVisor:
#   ./manifests/airgap-install/render.sh registry.example.com/substrate v0.1.0 \
#       --with-gvisor \
#       --gvisor-amd64-url=http://storage.internal/gvisor/runsc-amd64 \
#       --gvisor-amd64-sha256=f18a948bf9c8bbb54eb998549a3a8d719a1c7de2efbe8fdd2ff0ee5fecd06f19 \
#       --gvisor-arm64-url=http://storage.internal/gvisor/runsc-arm64 \
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
WITH_GVISOR="false"

for arg in "$@"; do
  case "${arg}" in
    --gvisor-amd64-url=*)       GVISOR_AMD64_URL="${arg#--gvisor-amd64-url=}" ;;
    --gvisor-amd64-sha256=*)    GVISOR_AMD64_SHA256="${arg#--gvisor-amd64-sha256=}" ;;
    --gvisor-arm64-url=*)       GVISOR_ARM64_URL="${arg#--gvisor-arm64-url=}" ;;
    --gvisor-arm64-sha256=*)    GVISOR_ARM64_SHA256="${arg#--gvisor-arm64-sha256=}" ;;
    --otel-endpoint=*)          OTEL_ENDPOINT="${arg#--otel-endpoint=}" ;;
    --with-gvisor)              WITH_GVISOR="true" ;;
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
echo "    REGISTRY:    ${REGISTRY}"
echo "    IMAGE_TAG:   ${IMAGE_TAG}"
echo "    WITH_GVISOR: ${WITH_GVISOR}"
echo "    OUTPUT:      ${OUT}/"
echo ""

# Files without placeholders are copied as-is
for f in 00-crds.yaml 01-namespaces.yaml 02-rbac.yaml 03-admission-policy.yaml; do
  cp "${DIR}/${f}" "${OUT}/${f}"
  echo "  copied:   ${OUT}/${f}"
done

# 04-sandboxconfig.yaml — only render if gVisor is explicitly requested
if [[ "${WITH_GVISOR}" == "true" ]]; then
  render_file "04-sandboxconfig.yaml"
  echo "  (gVisor SandboxConfig included — ensure runsc nodes are available)"
else
  echo "  skipped:  04-sandboxconfig.yaml  (pass --with-gvisor to include)"
fi

# Remaining files always get rendered
for f in \
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
if [[ "${WITH_GVISOR}" == "true" ]]; then
  echo "  # Step 2: gVisor SandboxConfig"
  echo "  kubectl apply -f ${OUT}/04-sandboxconfig.yaml"
  echo ""
fi
echo "  # Step 2: Pod certificate controller (must come before secrets)"
echo "  kubectl apply -f ${OUT}/05-pod-certificate-controller.yaml"
echo "  kubectl rollout status deployment/podcertificate-controller \\"
echo "    -n acr-substrate-podcert-ctrl-system --timeout=120s"
echo ""
echo "  # Step 3: Create required secrets and ConfigMaps"
echo "  ./hack/airgap/setup-secrets.sh"
echo ""
echo "  # Step 4: Core system components"
echo "  kubectl apply -f ${OUT}/06-valkey.yaml"
echo "  kubectl apply -f ${OUT}/07-rustfs.yaml"
echo "  kubectl apply -f ${OUT}/08-ate-api-server.yaml"
echo "  kubectl apply -f ${OUT}/09-ate-controller.yaml"
echo "  kubectl apply -f ${OUT}/10-atenet-router.yaml"
echo "  kubectl apply -f ${OUT}/11-atenet-dns.yaml"
echo "  kubectl apply -f ${OUT}/12-atelet.yaml"
