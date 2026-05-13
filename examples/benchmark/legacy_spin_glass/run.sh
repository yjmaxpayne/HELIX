#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_DIR="${HELIX_BUILD_DIR:-${ROOT_DIR}/build/cmake}"
OUTPUT_DIR="${HELIX_BENCHMARK_OUTPUT_DIR:-${BUILD_DIR}/example-benchmark/legacy_spin_glass}"
BENCHMARK_EXE="${BUILD_DIR}/legacy_spin_glass_benchmark"
WITH_NSIGHT="${HELIX_BENCHMARK_WITH_NSIGHT:-off}"
SKIP_BUILD=0

run_with_sanitized_profile_env()
{
	local env_args=()
	local env_name

	# Nsight reports record process environments, so strip common secret-like names.
	while IFS='=' read -r env_name _; do
		case "${env_name}" in
			*KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*CREDENTIAL*)
				env_args+=("-u" "${env_name}")
				;;
		esac
	done < <(env)

	env "${env_args[@]}" "$@"
}

for arg in "$@"; do
	case "${arg}" in
		--no-build)
			SKIP_BUILD=1
			;;
		-h|--help)
			cat <<'USAGE'
Usage: examples/benchmark/legacy_spin_glass/run.sh [--no-build]

Environment:
  HELIX_BUILD_DIR                 Build tree, default: build/cmake
  HELIX_BENCHMARK_OUTPUT_DIR      Artifact root, default: <build>/example-benchmark/legacy_spin_glass
  HELIX_BENCHMARK_WITH_NSIGHT     off | systems | nsys, default: off
  HELIX_BENCHMARK_CORRECTNESS_GATE_STATUS  not_run | passed | failed, default: not_run
  HELIX_BENCHMARK_BASELINE_GATE_STATUS     not_run | passed | failed, default: not_run
  HELIX_NSYS                      Optional path to nsys

Nsight launches are sanitized by removing environment variables whose names
contain KEY, TOKEN, SECRET, PASSWORD, or CREDENTIAL before profiling.
USAGE
			exit 0
			;;
		*)
			echo "unknown argument: ${arg}" >&2
			exit 2
			;;
	esac
done

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
	cmake --build "${BUILD_DIR}" --target legacy_spin_glass_benchmark --parallel "${HELIX_BUILD_JOBS:-$(nproc)}"
fi

if [[ ! -x "${BENCHMARK_EXE}" ]]; then
	echo "benchmark executable not found: ${BENCHMARK_EXE}" >&2
	echo "configure first with: cmake -S . -B ${BUILD_DIR} -DCMAKE_BUILD_TYPE=Release" >&2
	exit 1
fi

mkdir -p "${OUTPUT_DIR}/nsight"

case "${WITH_NSIGHT}" in
	off|0|false|no)
		HELIX_BENCHMARK_OUTPUT_DIR="${OUTPUT_DIR}" \
			"${BENCHMARK_EXE}"
		;;
	systems|nsys|1|true|yes)
		NSYS="${HELIX_NSYS:-}"
		if [[ -z "${NSYS}" ]]; then
			if command -v nsys >/dev/null 2>&1; then
				NSYS="$(command -v nsys)"
			elif [[ -x /usr/local/cuda-13.0/bin/nsys ]]; then
				NSYS=/usr/local/cuda-13.0/bin/nsys
			else
				echo "nsys not found; install NVIDIA Nsight Systems or set HELIX_NSYS" >&2
				exit 1
			fi
		fi
		run_id="$(date -u +%Y%m%dT%H%M%SZ)-legacy-spin-glass"
		report_base="${OUTPUT_DIR}/nsight/${run_id}-systems"
		HELIX_BENCHMARK_OUTPUT_DIR="${OUTPUT_DIR}" \
		HELIX_BENCHMARK_NSIGHT_ARTIFACT="nsight/${run_id}-systems.nsys-rep" \
			run_with_sanitized_profile_env "${NSYS}" profile \
				--force-overwrite true \
				--trace=cuda,nvtx,osrt \
				--output "${report_base}" \
				"${BENCHMARK_EXE}"
		;;
	*)
		echo "unsupported HELIX_BENCHMARK_WITH_NSIGHT=${WITH_NSIGHT}; use off or systems" >&2
		exit 2
		;;
esac

test -s "${OUTPUT_DIR}/helix_benchmark.jsonl"
test -s "${OUTPUT_DIR}/helix_benchmark_summary.md"
test -d "${OUTPUT_DIR}/nsight"

echo "benchmark example artifacts: ${OUTPUT_DIR}"
echo "  JSONL: ${OUTPUT_DIR}/helix_benchmark.jsonl"
echo "  summary: ${OUTPUT_DIR}/helix_benchmark_summary.md"
echo "  nsight: ${OUTPUT_DIR}/nsight"
