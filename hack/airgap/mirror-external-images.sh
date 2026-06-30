#!/usr/bin/env bash
# Pulls all external images required by substrate and pushes them to a private registry.
#
# Usage:
#   ./hack/airgap/mirror-external-images.sh <REGISTRY>
#
# Example:
#   ./hack/airgap/mirror-external-images.sh registry.example.com/substrate
#
# The script retags each image to use the provided REGISTRY as prefix so the
# air-gapped manifests in manifests/airgap-install/ can reference them.
#
# Prerequisites:
#   - Docker logged in to both the source registries (or images already pulled)
#     and the target REGISTRY
#   - Run this script on a machine with internet access, then ensure the images
#     are available in your air-gapped registry before deploying.

set -o errexit -o nounset -o pipefail

REGISTRY="${1:?Usage: $0 <REGISTRY>}"

echo "==> Mirroring external images to ${REGISTRY}"
echo ""

mirror() {
  local src="$1"
  local dst_tag="$2"
  local dst="${REGISTRY}/${dst_tag}"

  echo "--> ${src}"
  echo "    -> ${dst}"
  docker pull "${src}"
  docker tag  "${src}" "${dst}"
  docker push "${dst}"
  echo ""
}

# --- Base image used during Docker builds ---
mirror "gcr.io/distroless/static-debian13"     "distroless/static-debian13:latest"

# --- atenet-router: Envoy proxy sidecar ---
mirror "envoyproxy/envoy:v1.30-latest"          "envoy:v1.30"

# --- Valkey (Redis-compatible cluster cache) ---
mirror "valkey/valkey:9.1@sha256:4963247afc4cd33c7d3b2d2816b9f7f8eeebab148d29056c2ca4d7cbc966f2d9" \
       "valkey:9.1"

# --- atenet-dns: init container + CoreDNS ---
mirror "busybox:1.36"                           "busybox:1.36"
mirror "coredns/coredns:1.11.1"                 "coredns:1.11.1"

# --- RustFS (S3-compatible snapshot storage) ---
mirror "rustfs/rustfs:1.0.0-beta.3@sha256:378642b05b7dcb4849fb77ebe6aca4ced1c3f66e7e504247df95a5c9018d3358" \
       "rustfs:1.0.0-beta.3"

# --- RustFS bucket init job ---
mirror "amazon/aws-cli:2.17.0@sha256:643507c10ada7964ca6157b3d799f030b90577643da9955d319a77399ed80d73" \
       "aws-cli:2.17.0"

# --- pause image (used as ActorTemplate.spec.pauseImage in WorkerPools) ---
mirror "registry.k8s.io/pause:3.10.2@sha256:f548e0e8e3dc1896ca956272154dde3314e8cc4fde0a57577ee9fa1c63f5baf4" \
       "pause:3.10.2"

echo "==> All external images mirrored successfully."
echo ""
echo "Image map (source → ${REGISTRY}/...):"
echo "  envoyproxy/envoy:v1.30-latest          → ${REGISTRY}/envoy:v1.30"
echo "  valkey/valkey:9.1                       → ${REGISTRY}/valkey:9.1"
echo "  busybox:1.36                            → ${REGISTRY}/busybox:1.36"
echo "  coredns/coredns:1.11.1                  → ${REGISTRY}/coredns:1.11.1"
echo "  rustfs/rustfs:1.0.0-beta.3              → ${REGISTRY}/rustfs:1.0.0-beta.3"
echo "  amazon/aws-cli:2.17.0                   → ${REGISTRY}/aws-cli:2.17.0"
echo "  registry.k8s.io/pause:3.10.2            → ${REGISTRY}/pause:3.10.2"
echo ""
echo "NOTE: gVisor 'runsc' binary (optional — skip if not using gVisor sandboxes)."
echo "  If your cluster nodes have gVisor enabled, download the runsc binary and"
echo "  host it on an internal HTTP/S3 server:"
echo "    AMD64: gs://gvisor/releases/release/20260622/x86_64/runsc"
echo "    ARM64: gs://gvisor/releases/release/20260622/aarch64/runsc"
echo "  Then pass --with-gvisor and the --gvisor-* flags to render.sh."
echo "  For runc/regular containers (no gVisor), no action needed."
echo ""
echo "Next: run ./manifests/airgap-install/render.sh ${REGISTRY} <IMAGE_TAG>"
