#!/usr/bin/env bash
# Builds all substrate Go binaries as Docker images and pushes them to a private registry.
#
# Usage:
#   ./hack/airgap/build-substrate-images.sh <REGISTRY> <IMAGE_TAG>
#
# Example:
#   ./hack/airgap/build-substrate-images.sh registry.example.com/substrate v0.1.0
#
# Prerequisites:
#   - Docker with buildx support (multi-arch builds)
#   - Logged in to REGISTRY
#   - Run from the repository root

set -o errexit -o nounset -o pipefail

REGISTRY="${1:?Usage: $0 <REGISTRY> <IMAGE_TAG>}"
IMAGE_TAG="${2:?Usage: $0 <REGISTRY> <IMAGE_TAG>}"
ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

PLATFORMS="linux/amd64,linux/arm64"

# Version stamp from git if not building a pinned tag
VERSION="${IMAGE_TAG}"

echo "==> Building substrate images"
echo "    REGISTRY:  ${REGISTRY}"
echo "    IMAGE_TAG: ${IMAGE_TAG}"
echo "    PLATFORMS: ${PLATFORMS}"
echo ""

# Ensure a multi-arch builder exists
if ! docker buildx inspect substrate-builder >/dev/null 2>&1; then
  docker buildx create --name substrate-builder --use
else
  docker buildx use substrate-builder
fi

build_and_push() {
  local name="$1"
  local dockerfile="$2"
  local full_image="${REGISTRY}/substrate-${name}:${IMAGE_TAG}"

  echo "--> Building ${full_image}"
  docker buildx build \
    --platform "${PLATFORMS}" \
    --file "${dockerfile}" \
    --build-arg "VERSION=${VERSION}" \
    --tag "${full_image}" \
    --push \
    .

  echo "    Pushed: ${full_image}"
}

build_and_push "ateapi"           "build/dockerfiles/Dockerfile.ateapi"
build_and_push "atelet"           "build/dockerfiles/Dockerfile.atelet"
build_and_push "atecontroller"    "build/dockerfiles/Dockerfile.atecontroller"
build_and_push "atenet"           "build/dockerfiles/Dockerfile.atenet"
build_and_push "podcertcontroller" "build/dockerfiles/Dockerfile.podcertcontroller"
build_and_push "ateom-gvisor"     "build/dockerfiles/Dockerfile.ateom-gvisor"

echo ""
echo "==> All substrate images built and pushed successfully."
echo ""
echo "Image summary:"
echo "  ${REGISTRY}/substrate-ateapi:${IMAGE_TAG}"
echo "  ${REGISTRY}/substrate-atelet:${IMAGE_TAG}"
echo "  ${REGISTRY}/substrate-atecontroller:${IMAGE_TAG}"
echo "  ${REGISTRY}/substrate-atenet:${IMAGE_TAG}"
echo "  ${REGISTRY}/substrate-podcertcontroller:${IMAGE_TAG}"
echo "  ${REGISTRY}/substrate-ateom-gvisor:${IMAGE_TAG}"
echo ""
echo "Next: run ./hack/airgap/mirror-external-images.sh ${REGISTRY}"
