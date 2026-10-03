#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/run_legacy_spin_glass_t11_ablation_benchmark.sh" "$@"

usage() {
    cat <<'USAGE'
Usage:
  scripts/run_legacy_spin_glass_before_after_benchmark.sh \
    --pre-ref <ref> \
    --post-ref <ref> \
    [--runs 10] \
    [--warmup-steps 10] \
    [--steady-steps 200] \
    [--artifact-root /tmp/helix-e2e-before-after-YYYYMMDD] \
    [--build-type Release] \
    [--cuda-architectures native] \
    [--jobs N] \
    [--post-dirty-worktree] \
    [--report .plan/v0.0.4-helix-gpu-heom-optimize-plan/11-end-to-end-before-after-report.md]

Creates detached clean git worktrees and independent CMake build trees under the artifact root.
The current working tree is never checked out or modified by the benchmark run.
With --post-dirty-worktree, the post side is an explicit exploratory copy of the current
working tree and the report is marked dirty_worktree_exploratory.
USAGE
}

log() {
    printf '[helix-before-after] %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

pre_ref=""
post_ref=""
runs="10"
warmup_steps="10"
steady_steps="100"
artifact_root=""
build_type="Release"
cuda_architectures="${HELIX_CUDA_ARCHITECTURES:-native}"
jobs="$(nproc)"
report_path=".plan/v0.0.4-helix-gpu-heom-optimize-plan/11-end-to-end-before-after-report.md"
post_dirty_worktree=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pre-ref)
            pre_ref="${2:-}"
            shift 2
            ;;
        --post-ref)
            post_ref="${2:-}"
            shift 2
            ;;
        --runs)
            runs="${2:-}"
            shift 2
            ;;
        --warmup-steps)
            warmup_steps="${2:-}"
            shift 2
            ;;
        --steady-steps)
            steady_steps="${2:-}"
            shift 2
            ;;
        --artifact-root)
            artifact_root="${2:-}"
            shift 2
            ;;
        --build-type)
            build_type="${2:-}"
            shift 2
            ;;
        --cuda-architectures)
            cuda_architectures="${2:-}"
            shift 2
            ;;
        --jobs)
            jobs="${2:-}"
            shift 2
            ;;
        --post-dirty-worktree)
            post_dirty_worktree=1
            shift
            ;;
        --report)
            report_path="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$pre_ref" ]] || die "--pre-ref is required"
if [[ "$post_dirty_worktree" -eq 0 ]]; then
    [[ -n "$post_ref" ]] || die "--post-ref is required unless --post-dirty-worktree is used"
else
    if [[ -z "$post_ref" ]]; then
        post_ref="current-dirty-worktree"
    fi
fi
[[ "$runs" =~ ^[0-9]+$ && "$runs" -gt 0 ]] || die "--runs must be a positive integer"
[[ "$warmup_steps" =~ ^[0-9]+$ && "$warmup_steps" -gt 0 ]] || die "--warmup-steps must be a positive integer"
[[ "$steady_steps" =~ ^[0-9]+$ && "$steady_steps" -gt 0 ]] || die "--steady-steps must be a positive integer"
[[ "$jobs" =~ ^[0-9]+$ && "$jobs" -gt 0 ]] || die "--jobs must be a positive integer"

require_command git
require_command cmake
require_command python3
if [[ "$post_dirty_worktree" -eq 1 ]]; then
    require_command tar
fi

repo_root="$(git rev-parse --show-toplevel)"
if [[ -z "$artifact_root" ]]; then
    artifact_root="/tmp/helix-e2e-before-after-$(date -u +%Y%m%dT%H%M%SZ)"
fi
if [[ "$report_path" != /* ]]; then
    report_path="$repo_root/$report_path"
fi
artifact_root="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$artifact_root")"
report_path="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$report_path")"

if [[ -e "$artifact_root" ]]; then
    existing_entry="$(find "$artifact_root" -mindepth 1 -maxdepth 1 -print -quit)"
    [[ -z "$existing_entry" ]] || die "artifact root already exists and is not empty: $artifact_root"
fi

mkdir -p "$artifact_root/raw" "$artifact_root/worktrees" "$artifact_root/builds" "$artifact_root/logs"

if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi > "$artifact_root/nvidia-smi.txt" || true
fi

add_worktree() {
    local label="$1"
    local ref="$2"
    local worktree="$artifact_root/worktrees/$label"
    local log_file="$artifact_root/logs/${label}_worktree.log"

    log "creating clean worktree for $label at $worktree from $ref"
    git -C "$repo_root" worktree add --detach "$worktree" "$ref" > "$log_file" 2>&1
    printf '%s\n' "$worktree"
}

copy_dirty_worktree() {
    local snapshot="$artifact_root/worktrees/post-dirty-worktree"
    log "copying current dirty worktree for exploratory post benchmark at $snapshot"
    mkdir -p "$snapshot"
    tar \
        --exclude=.git \
        --exclude=build \
        --exclude=.cache \
        --exclude=.venv \
        --exclude='output.txt' \
        --exclude='outputEnergy.txt' \
        --exclude='output_rho*.txt' \
        --exclude='snapshot_rho*.dat' \
        -cf - -C "$repo_root" . | tar -xf - -C "$snapshot"
    printf '%s\n' "$snapshot"
}

configure_and_build() {
    local label="$1"
    local worktree="$2"
    local ref_status="$3"
    local build_dir="$artifact_root/builds/$label"
    local raw_dir="$artifact_root/raw/$label"

    mkdir -p "$raw_dir"
    printf '%s\n' "$ref_status" > "$raw_dir/ref_status.txt"
    if git -C "$worktree" rev-parse HEAD > "$raw_dir/git_rev.txt" 2> /dev/null; then
        git -C "$worktree" status --short > "$raw_dir/git_status.txt"
    else
        git -C "$repo_root" rev-parse HEAD > "$raw_dir/git_rev.txt"
        git -C "$repo_root" status --short > "$raw_dir/git_status.txt"
    fi
    if [[ "$ref_status" == "clean_worktree" && -s "$raw_dir/git_status.txt" ]]; then
        die "$label worktree is not clean; refusing final benchmark. See $raw_dir/git_status.txt"
    fi

    log "configuring $label build"
    cmake -S "$worktree" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE="$build_type" \
        -DHELIX_CUDA_ARCHITECTURES="$cuda_architectures" \
        > "$artifact_root/logs/${label}_cmake_configure.log" 2>&1

    log "building $label benchmark target"
    cmake --build "$build_dir" --target legacy_spin_glass_benchmark --parallel "$jobs" \
        > "$artifact_root/logs/${label}_build.log" 2>&1

    printf '%s\n' "$build_dir"
}

run_benchmark_set() {
    local label="$1"
    local ref="$2"
    local worktree="$3"
    local build_dir="$4"
    local raw_dir="$artifact_root/raw/$label"
    local benchmark="$build_dir/legacy_spin_glass_benchmark"
    local head
    local git_dirty

    head="$(<"$raw_dir/git_rev.txt")"
    git_dirty=0
    if [[ "$(<"$raw_dir/ref_status.txt")" != "clean_worktree" ]]; then
        git_dirty=1
    fi
    [[ -x "$benchmark" ]] || die "benchmark executable not found: $benchmark"
    printf '%s\n' "$ref" > "$raw_dir/requested_ref.txt"
    printf '%s\n' "$build_type" > "$raw_dir/build_type.txt"
    printf '%s\n' "$cuda_architectures" > "$raw_dir/cuda_architectures.txt"
    printf '%s\n' "$warmup_steps" > "$raw_dir/warmup_steps.txt"
    printf '%s\n' "$steady_steps" > "$raw_dir/steady_steps.txt"
    : > "$raw_dir/helix_benchmark.jsonl"

    log "running unrecorded device warmup for $label"
    mkdir -p "$raw_dir/unrecorded-warmup"
    env \
        HELIX_BENCHMARK_OUTPUT_DIR="$raw_dir/unrecorded-warmup" \
        HELIX_BENCHMARK_WARMUP_STEPS="$warmup_steps" \
        HELIX_BENCHMARK_STEADY_STEPS="$steady_steps" \
        HELIX_BENCHMARK_CAPTURE_CALIBRATION=0 \
        HELIX_BENCHMARK_GIT_COMMIT="$head" \
        HELIX_BENCHMARK_GIT_DIRTY="$git_dirty" \
        HELIX_BENCHMARK_HOST_RUNNER="before_after_runner" \
        "$benchmark" > "$raw_dir/unrecorded-warmup/stdout.jsonl" 2> "$raw_dir/unrecorded-warmup/stderr.log"

    for run_id in $(seq 1 "$runs"); do
        local run_name
        local run_dir
        run_name="$(printf 'run-%02d' "$run_id")"
        run_dir="$raw_dir/runs/$run_name"
        mkdir -p "$run_dir"
        log "running $label $run_name/$runs"
        env \
            HELIX_BENCHMARK_OUTPUT_DIR="$run_dir" \
            HELIX_BENCHMARK_WARMUP_STEPS="$warmup_steps" \
            HELIX_BENCHMARK_STEADY_STEPS="$steady_steps" \
            HELIX_BENCHMARK_CAPTURE_CALIBRATION=0 \
            HELIX_BENCHMARK_GIT_COMMIT="$head" \
            HELIX_BENCHMARK_GIT_DIRTY="$git_dirty" \
            HELIX_BENCHMARK_HOST_RUNNER="before_after_runner" \
            "$benchmark" > "$run_dir/stdout.jsonl" 2> "$run_dir/stderr.log"
        [[ -s "$run_dir/helix_benchmark.jsonl" ]] || die "missing benchmark JSONL for $label $run_name"
        cat "$run_dir/helix_benchmark.jsonl" >> "$raw_dir/helix_benchmark.jsonl"
    done
}

pre_worktree="$(add_worktree pre "$pre_ref")"
if [[ "$post_dirty_worktree" -eq 1 ]]; then
    post_worktree="$(copy_dirty_worktree)"
    post_ref_status="dirty_worktree_exploratory"
else
    post_worktree="$(add_worktree post "$post_ref")"
    post_ref_status="clean_worktree"
fi
pre_build="$(configure_and_build pre "$pre_worktree" "clean_worktree")"
post_build="$(configure_and_build post "$post_worktree" "$post_ref_status")"
run_benchmark_set pre "$pre_ref" "$pre_worktree" "$pre_build"
run_benchmark_set post "$post_ref" "$post_worktree" "$post_build"

python3 - "$artifact_root" "$report_path" "$runs" "$warmup_steps" "$steady_steps" <<'PY'
import json
import math
import os
import statistics
import sys
from pathlib import Path

artifact_root = Path(sys.argv[1])
report_path = Path(sys.argv[2])
runs_requested = int(sys.argv[3])
warmup_steps = int(sys.argv[4])
steady_steps = int(sys.argv[5])

def read_text(path):
    return path.read_text(encoding="utf-8").strip()

def read_records(label):
    path = artifact_root / "raw" / label / "helix_benchmark.jsonl"
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            records.append(json.loads(line))
    return records

def stats(values):
    values = [float(value) for value in values if value is not None and math.isfinite(float(value))]
    if not values:
        return {"count": 0, "median": None, "min": None, "max": None, "stdev": None}
    return {
        "count": len(values),
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
        "stdev": statistics.stdev(values) if len(values) > 1 else 0.0,
    }

def nested(record, *keys):
    current = record
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current

def numeric_nested(record, *keys):
    value = nested(record, *keys)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None

def steady_ms_per_step(record):
    steady = numeric_nested(record, "timing_ms", "steady_propagation")
    steps = numeric_nested(record, "problem", "steady_steps")
    if steady is None or steps is None or steps <= 0:
        return None
    return steady / steps

def main_total_ms(record):
    timing = record.get("timing_ms", {})
    names = ("init", "warmup", "steady_propagation", "result_extraction", "teardown")
    values = [timing.get(name) for name in names]
    if not all(isinstance(value, (int, float)) for value in values):
        return None
    return float(sum(values))

def result_extraction_ms(record):
    return numeric_nested(record, "timing_ms", "result_extraction")

def counter(record, group, field):
    return numeric_nested(record, "profiling", "counters", group, field)

def metric_values(records, metric):
    if metric == "steady_propagation_ms_per_step":
        return [steady_ms_per_step(record) for record in records]
    if metric == "benchmark_main_total_ms":
        return [main_total_ms(record) for record in records]
    if metric == "result_extraction_total_ms":
        return [result_extraction_ms(record) for record in records]
    group, field = metric.split(".", 1)
    return [counter(record, group, field) for record in records]

def fmt(value):
    if value is None:
        return "not_available_in_ref"
    if abs(value) >= 1000:
        return f"{value:.3f}"
    return f"{value:.6g}"

def ratio(post, pre):
    if post is None or pre is None or pre == 0:
        return None
    return post / pre

pre_records = read_records("pre")
post_records = read_records("post")

def label_meta(label):
    raw = artifact_root / "raw" / label
    return {
        "requested_ref": read_text(raw / "requested_ref.txt"),
        "resolved_head": read_text(raw / "git_rev.txt"),
        "git_status_short": read_text(raw / "git_status.txt"),
        "build_type": read_text(raw / "build_type.txt"),
        "cuda_architectures": read_text(raw / "cuda_architectures.txt"),
        "warmup_steps": int(read_text(raw / "warmup_steps.txt")),
        "steady_steps": int(read_text(raw / "steady_steps.txt")),
        "jsonl": str(raw / "helix_benchmark.jsonl"),
        "runs_recorded": len(pre_records) if label == "pre" else len(post_records),
        "ref_status": read_text(raw / "ref_status.txt"),
    }

manifest = {
    "artifact_root": str(artifact_root),
    "runs_requested": runs_requested,
    "warmup_steps": warmup_steps,
    "steady_steps": steady_steps,
    "pre": label_meta("pre"),
    "post": label_meta("post"),
}
(artifact_root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

comparison_keys = [
    ("gpu.name", ("gpu", "name")),
    ("cuda.runtime_version", ("cuda", "runtime_version")),
    ("cuda.driver_version", ("cuda", "driver_version")),
    ("build.type", ("build", "type")),
    ("build.cuda_architectures", ("build", "cuda_architectures")),
    ("build.compiler", ("build", "compiler")),
    ("case.name", ("case", "name")),
    ("case.backend", ("case", "backend")),
    ("case.precision", ("case", "precision")),
    ("problem.N", ("problem", "N")),
    ("problem.KMax", ("problem", "KMax")),
    ("problem.JMax", ("problem", "JMax")),
    ("problem.hierarchy_size", ("problem", "hierarchy_size")),
    ("problem.time_step", ("problem", "time_step")),
    ("problem.integration_order", ("problem", "integration_order")),
    ("problem.warmup_steps", ("problem", "warmup_steps")),
    ("problem.steady_steps", ("problem", "steady_steps")),
]
pre_first = pre_records[0]
post_first = post_records[0]
mismatches = []
for name, keys in comparison_keys:
    pre_value = nested(pre_first, *keys)
    post_value = nested(post_first, *keys)
    if pre_value != post_value:
        mismatches.append((name, pre_value, post_value))

metrics = [
    ("steady_propagation_ms_per_step", "hot-path steady propagation per step"),
    ("benchmark_main_total_ms", "init + warmup + steady + extraction + teardown"),
    ("result_extraction_total_ms", "final reduced-density extraction"),
]
counters = [
    ("spmm.call_count", "SpMM call count"),
    ("spmm.descriptor_create_count", "SpMM descriptor creates"),
    ("spmm.workspace_alloc_count", "SpMM workspace allocations"),
    ("spmm.buffer_size_query_count", "SpMM buffer-size queries"),
    ("d2d_copy.copy_count", "D2D copy count"),
    ("d2d_copy.bytes", "D2D bytes"),
    ("transpose.call_count", "Transpose call count"),
    ("transpose.bytes", "Transpose bytes"),
]

metric_rows = []
for metric, description in metrics:
    pre_stats = stats(metric_values(pre_records, metric))
    post_stats = stats(metric_values(post_records, metric))
    metric_rows.append((metric, description, pre_stats, post_stats, ratio(post_stats["median"], pre_stats["median"])))

counter_rows = []
for metric, description in counters:
    pre_stats = stats(metric_values(pre_records, metric))
    post_stats = stats(metric_values(post_records, metric))
    counter_rows.append((metric, description, pre_stats, post_stats, ratio(post_stats["median"], pre_stats["median"])))

steady_pre = metric_rows[0][2]
steady_post = metric_rows[0][3]
steady_ratio = metric_rows[0][4]
def relative_noise(summary):
    if summary["median"] in (None, 0) or summary["stdev"] is None:
        return 1.0
    return abs(summary["stdev"] / summary["median"])
max_relative_noise = max(relative_noise(steady_pre), relative_noise(steady_post))
comparable = not mismatches and manifest["post"]["ref_status"] == "clean_worktree"
enough_runs = len(pre_records) >= 10 and len(post_records) >= 10
if not comparable or not enough_runs or steady_ratio is None or max_relative_noise >= 0.10:
    conclusion = "inconclusive_due_to_variance_or_build_mismatch"
elif abs(steady_ratio - 1.0) <= max(0.02, max_relative_noise * 2.0):
    conclusion = "within_noise"
elif steady_ratio < 1.0:
    conclusion = "overall_improved"
else:
    conclusion = "overall_regressed"

snippet = (
    f"{conclusion}: post/pre steady_propagation_ms_per_step={fmt(steady_ratio)} "
    f"({len(pre_records)} pre runs, {len(post_records)} post runs, "
    f"max relative stdev={fmt(max_relative_noise)})."
)

lines = []
lines.append("# HELIX end-to-end before/after benchmark report")
lines.append("")
if manifest["post"]["ref_status"] == "clean_worktree":
    lines.append("This report compares clean pre/post refs using the same runner script, build configuration, GPU, CUDA runtime, and legacy spin-glass problem shape.")
else:
    lines.append("This exploratory report compares a clean pre ref with a dirty post worktree snapshot using the same runner script, build configuration, GPU, CUDA runtime, and legacy spin-glass problem shape.")
lines.append("")
lines.append("## Verdict")
lines.append("")
lines.append(f"- Conclusion: `{conclusion}`")
lines.append(f"- Release / PR snippet: {snippet}")
if not enough_runs:
    lines.append("- Caveat: fewer than 10 recorded runs were collected for at least one ref; treat this as exploratory.")
if manifest["post"]["ref_status"] != "clean_worktree":
    lines.append(f"- Caveat: post_ref_status=`{manifest['post']['ref_status']}`; this cannot support a final release performance conclusion.")
if mismatches:
    lines.append("- Caveat: environment or problem-shape mismatches were detected; ratios are not final release evidence.")
lines.append("")
lines.append("## Inputs")
lines.append("")
lines.append("| Side | Requested ref | Resolved HEAD | Ref status | Runs | JSONL |")
lines.append("| --- | --- | --- | --- | ---: | --- |")
for label in ("pre", "post"):
    meta = manifest[label]
    lines.append(f"| {label} | `{meta['requested_ref']}` | `{meta['resolved_head']}` | `{meta['ref_status']}` | {meta['runs_recorded']} | `{meta['jsonl']}` |")
lines.append("")
lines.append("## Build And Problem Match")
lines.append("")
if mismatches:
    lines.append("| Field | Pre | Post |")
    lines.append("| --- | --- | --- |")
    for name, pre_value, post_value in mismatches:
        lines.append(f"| `{name}` | `{pre_value}` | `{post_value}` |")
else:
    lines.append("All compared build, GPU, CUDA, case, and problem-shape fields matched.")
lines.append("")
lines.append("## Timing Metrics")
lines.append("")
lines.append("| Metric | Meaning | Pre median | Pre min | Pre max | Pre stdev | Post median | Post min | Post max | Post stdev | Post/pre |")
lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for metric, description, pre_stats, post_stats, post_pre in metric_rows:
    lines.append(
        f"| `{metric}` | {description} | {fmt(pre_stats['median'])} | {fmt(pre_stats['min'])} | "
        f"{fmt(pre_stats['max'])} | {fmt(pre_stats['stdev'])} | {fmt(post_stats['median'])} | "
        f"{fmt(post_stats['min'])} | {fmt(post_stats['max'])} | {fmt(post_stats['stdev'])} | {fmt(post_pre)} |"
    )
lines.append("")
lines.append("## Counter Attribution")
lines.append("")
lines.append("Counters are explanatory evidence only. Missing fields in older refs are reported as `not_available_in_ref` and are not used as release blockers.")
lines.append("")
lines.append("| Counter | Meaning | Pre median | Post median | Post/pre |")
lines.append("| --- | --- | ---: | ---: | ---: |")
for metric, description, pre_stats, post_stats, post_pre in counter_rows:
    lines.append(f"| `{metric}` | {description} | {fmt(pre_stats['median'])} | {fmt(post_stats['median'])} | {fmt(post_pre)} |")
lines.append("")
lines.append("## Raw Artifacts")
lines.append("")
lines.append(f"- Artifact root: `{artifact_root}`")
lines.append(f"- Manifest: `{artifact_root / 'manifest.json'}`")
lines.append(f"- GPU snapshot: `{artifact_root / 'nvidia-smi.txt'}`")
lines.append(f"- Logs: `{artifact_root / 'logs'}`")
lines.append("")
lines.append("## Rerun Conditions")
lines.append("")
lines.append("- Use clean committed refs for both `--pre-ref` and `--post-ref` before claiming final release performance.")
lines.append("- Use at least `--runs 10`; if local resources require fewer runs, keep the conclusion exploratory.")
lines.append("- Keep `--warmup-steps`, `--steady-steps`, build type, CUDA architecture, GPU, and CUDA toolkit identical across refs.")
lines.append("")

report = "\n".join(lines)
(artifact_root / "end-to-end-before-after-report.md").write_text(report, encoding="utf-8")
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(report, encoding="utf-8")
PY

log "before/after benchmark complete"
log "artifact root: $artifact_root"
log "report: $report_path"
