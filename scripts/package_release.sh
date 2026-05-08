#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-${HELIX_RELEASE_TAG:-dev}}"
BUILD_DIR="${2:-${HELIX_BUILD_DIR:-"${ROOT_DIR}/build/cmake"}}"
DIST_DIR="${3:-${HELIX_DIST_DIR:-"${ROOT_DIR}/dist"}}"
CUDA_ARCHITECTURES="${HELIX_CUDA_ARCHITECTURES:-${HEOM_CUDA_ARCHITECTURES:-native}}"
CUDA_VERSION="$("${CUDACXX:-nvcc}" --version | awk -F'release ' '/release/ {split($2, version, ","); print version[1]; exit}')"
SOURCE_REVISION="${GITHUB_SHA:-$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)}"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ ! -x "${BUILD_DIR}/helix" ]]; then
    echo "Release binary not found or not executable: ${BUILD_DIR}/helix" >&2
    echo "Run scripts/verify_examples.sh or cmake --build before packaging." >&2
    exit 1
fi

arch_label="${CUDA_ARCHITECTURES//[^0-9A-Za-z_.-]/_}"
cuda_major="${CUDA_VERSION%%.*}"
if [[ -z "${cuda_major}" ]]; then
    cuda_label="cudaunknown"
else
    cuda_label="cuda${cuda_major}"
fi
package_name="helix-${TAG}-linux-x86_64-${cuda_label}-sm${arch_label}"
package_root="${DIST_DIR}/${package_name}"
tarball="${DIST_DIR}/${package_name}.tar.gz"
checksum="${tarball}.sha256"

rm -rf -- "${package_root}" "${tarball}" "${checksum}"
mkdir -p "${package_root}/bin" "${package_root}/examples"

install -m 0755 "${BUILD_DIR}/helix" "${package_root}/bin/helix"
install -m 0644 "${ROOT_DIR}/README.md" "${package_root}/README.md"
install -m 0644 "${ROOT_DIR}/LICENSE" "${package_root}/LICENSE"
install -m 0644 "${ROOT_DIR}/examples/outputEnergy.txt" "${package_root}/examples/outputEnergy.txt"

cat > "${package_root}/manifest.txt" <<MANIFEST
name: HELIX
version: ${TAG}
target: linux-x86_64
cuda_version: ${CUDA_VERSION:-unknown}
cuda_architectures: ${CUDA_ARCHITECTURES}
source_revision: ${SOURCE_REVISION}
built_at: ${BUILT_AT}
binary: bin/helix
baseline: examples/outputEnergy.txt
MANIFEST

tar -C "${DIST_DIR}" -czf "${tarball}" "${package_name}"
(
    cd "${DIST_DIR}"
    sha256sum "$(basename "${tarball}")" > "$(basename "${checksum}")"
)

echo "Created ${tarball}"
echo "Created ${checksum}"
