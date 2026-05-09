#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${HELIX_BUILD_DIR:-${HEOM_BUILD_DIR:-"${ROOT_DIR}/build/cmake"}}"
RUN_DIR="${HELIX_RUN_DIR:-${HEOM_RUN_DIR:-"${BUILD_DIR}/example-run"}}"
STEPS="${HELIX_STEPS:-${HEOM_STEPS:-1980}}"
ENERGY_TOL="${HELIX_ENERGY_TOL:-${HEOM_ENERGY_TOL:-1e-5}}"
BUILD_JOBS="${HELIX_BUILD_JOBS:-${HEOM_BUILD_JOBS:-$(nproc)}}"

cmake_args=(
    -S "${ROOT_DIR}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
)

if [[ -n "${HELIX_CUDA_ARCHITECTURES:-}" ]]; then
    cmake_args+=("-DHELIX_CUDA_ARCHITECTURES=${HELIX_CUDA_ARCHITECTURES}")
elif [[ -n "${HEOM_CUDA_ARCHITECTURES:-}" ]]; then
    cmake_args+=("-DHEOM_CUDA_ARCHITECTURES=${HEOM_CUDA_ARCHITECTURES}")
fi

cmake "${cmake_args[@]}"
cmake --build "${BUILD_DIR}" --parallel "${BUILD_JOBS}"

mkdir -p "${RUN_DIR}"
SUMMARY_FILE="${HELIX_COMPARE_SUMMARY:-${RUN_DIR}/energy_compare_summary.txt}"
mkdir -p "$(dirname "${SUMMARY_FILE}")"
: > "${SUMMARY_FILE}"

echo "Running helix with HELIX_STEPS=${STEPS}"
(
    cd "${RUN_DIR}"
    /usr/bin/time -p env HELIX_STEPS="${STEPS}" "${BUILD_DIR}/helix"
)

awk -v tol="${ENERGY_TOL}" -v summary="${SUMMARY_FILE}" '
function emit_stdout(message) {
    print message
    print message >> summary
}
function emit_stderr(message) {
    print message > "/dev/stderr"
    print message >> summary
}
function fail(message) {
    emit_stderr(message)
    failed = 1
    exit 1
}
NR == FNR {
    ref_time[NR] = $1
    ref_energy[NR] = $2
    ref_count = NR
    next
}
{
    run_count = FNR
    if (FNR > ref_count) {
        fail(sprintf("run has more lines than reference at line %d", FNR))
    }
    dt = $1 - ref_time[FNR]
    if (dt < 0) dt = -dt
    de = $2 - ref_energy[FNR]
    if (de < 0) de = -de
    if (dt > max_dt) max_dt = dt
    if (de > max_de) max_de = de
    if (dt != 0 || de > tol) {
        fail(sprintf("mismatch line %d: ref=(%s,%s) run=(%s,%s) |dt|=%g |de|=%g tol=%g",
                     FNR, ref_time[FNR], ref_energy[FNR], $1, $2, dt, de, tol))
    }
}
END {
    if (failed) {
        exit 1
    }
    if (run_count == 0) {
        fail("run produced no outputEnergy rows")
    }
    emit_stdout(sprintf("outputEnergy prefix matched: lines=%d max_time_diff=%g max_energy_diff=%g tol=%g",
                        run_count, max_dt + 0, max_de + 0, tol))
}
' "${ROOT_DIR}/examples/outputEnergy.txt" "${RUN_DIR}/outputEnergy.txt"

echo "Outputs written to ${RUN_DIR}"
echo "Comparison summary written to ${SUMMARY_FILE}"
