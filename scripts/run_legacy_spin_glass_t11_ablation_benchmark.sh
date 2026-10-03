#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/run_legacy_spin_glass_before_after_benchmark.sh \
    --pre-ref <ref> \
    --post-ref <ref> \
    [--runs 10] \
    [--warmup-steps 10] \
    [--steady-steps 200] \
    [--artifact-root /tmp/helix-v005-t11-pure-timing] \
    [--build-type Release] \
    [--cuda-architectures native] \
    [--jobs N] \
    [--post-dirty-worktree] \
    [--report .plan/v0.0.4-helix-regression-recovery-and-runtime-ownership-plan/reports/t11-ablation-report.md]

Runs the T11 A0-A3 ablation matrix in isolated worktrees/builds:
  A0 pre harness                  pre ref, pure timing request
  A1 post pure timing             post ref, HELIX_BENCHMARK_COLLECT_BACKEND_PROFILING=0
  A2 post attribution             post ref, HELIX_BENCHMARK_COLLECT_BACKEND_PROFILING=1
  A3 post legacy wrapper fallback post ref, pure timing, HELIX_CUSPARSE_REUSE_PLAN=0

A4/A5 source-patch variants are recorded as not_run by this harness. Run a dedicated
3-run source-patch scout before T12 if A0-A3 do not identify a primary culprit.
USAGE
}

log() {
    printf '[helix-t11-ablation] %s\n' "$*" >&2
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
steady_steps="200"
artifact_root=""
build_type="Release"
cuda_architectures="${HELIX_CUDA_ARCHITECTURES:-native}"
jobs="$(nproc)"
report_path=".plan/v0.0.4-helix-regression-recovery-and-runtime-ownership-plan/reports/t11-ablation-report.md"
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
    artifact_root="/tmp/helix-t11-ablation-$(date -u +%Y%m%dT%H%M%SZ)"
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

write_variant_metadata() {
    local variant_dir="$1"
    local variant_id="$2"
    local variant_name="$3"
    local requested_ref="$4"
    local ref_status="$5"
    local timing_mode="$6"
    local collect_backend_profiling="$7"
    local reuse_plan="$8"
    local description="$9"

    printf '%s\n' "$variant_id" > "$variant_dir/variant_id.txt"
    printf '%s\n' "$variant_name" > "$variant_dir/variant_name.txt"
    printf '%s\n' "$requested_ref" > "$variant_dir/requested_ref.txt"
    printf '%s\n' "$ref_status" > "$variant_dir/ref_status.txt"
    printf '%s\n' "$timing_mode" > "$variant_dir/timing_mode.txt"
    printf '%s\n' "$collect_backend_profiling" > "$variant_dir/collect_backend_profiling.txt"
    printf '%s\n' "$reuse_plan" > "$variant_dir/cusparse_reuse_plan.txt"
    printf '%s\n' "$description" > "$variant_dir/description.txt"
    printf '%s\n' "$build_type" > "$variant_dir/build_type.txt"
    printf '%s\n' "$cuda_architectures" > "$variant_dir/cuda_architectures.txt"
    printf '%s\n' "$warmup_steps" > "$variant_dir/warmup_steps.txt"
    printf '%s\n' "$steady_steps" > "$variant_dir/steady_steps.txt"
}

run_benchmark_variant() {
    local variant_label="$1"
    local variant_id="$2"
    local variant_name="$3"
    local requested_ref="$4"
    local worktree="$5"
    local build_dir="$6"
    local ref_status="$7"
    local timing_mode="$8"
    local collect_backend_profiling="$9"
    local reuse_plan="${10}"
    local description="${11}"
    local raw_dir="$artifact_root/raw/$variant_label"
    local benchmark="$build_dir/legacy_spin_glass_benchmark"
    local head
    local git_dirty

    mkdir -p "$raw_dir"
    write_variant_metadata \
        "$raw_dir" \
        "$variant_id" \
        "$variant_name" \
        "$requested_ref" \
        "$ref_status" \
        "$timing_mode" \
        "$collect_backend_profiling" \
        "$reuse_plan" \
        "$description"

    head="$(git -C "$worktree" rev-parse HEAD 2> /dev/null || git -C "$repo_root" rev-parse HEAD)"
    printf '%s\n' "$head" > "$raw_dir/git_rev.txt"
    git -C "$worktree" status --short > "$raw_dir/git_status.txt" 2> /dev/null || git -C "$repo_root" status --short > "$raw_dir/git_status.txt"

    git_dirty=0
    if [[ "$ref_status" != "clean_worktree" ]]; then
        git_dirty=1
    fi
    [[ -x "$benchmark" ]] || die "benchmark executable not found: $benchmark"
    : > "$raw_dir/helix_benchmark.jsonl"

    log "running unrecorded device warmup for $variant_id ($variant_name)"
    mkdir -p "$raw_dir/unrecorded-warmup"
    env \
        HELIX_BENCHMARK_OUTPUT_DIR="$raw_dir/unrecorded-warmup" \
        HELIX_BENCHMARK_WARMUP_STEPS="$warmup_steps" \
        HELIX_BENCHMARK_STEADY_STEPS="$steady_steps" \
        HELIX_BENCHMARK_CAPTURE_CALIBRATION=0 \
        HELIX_BENCHMARK_COLLECT_BACKEND_PROFILING="$collect_backend_profiling" \
        HELIX_CUSPARSE_REUSE_PLAN="$reuse_plan" \
        HELIX_BENCHMARK_GIT_COMMIT="$head" \
        HELIX_BENCHMARK_GIT_DIRTY="$git_dirty" \
        HELIX_BENCHMARK_HOST_RUNNER="t11_ablation/$variant_id" \
        "$benchmark" > "$raw_dir/unrecorded-warmup/stdout.jsonl" 2> "$raw_dir/unrecorded-warmup/stderr.log"

    for run_id in $(seq 1 "$runs"); do
        local run_name
        local run_dir
        run_name="$(printf 'run-%02d' "$run_id")"
        run_dir="$raw_dir/runs/$run_name"
        mkdir -p "$run_dir"
        log "running $variant_id $run_name/$runs"
        env \
            HELIX_BENCHMARK_OUTPUT_DIR="$run_dir" \
            HELIX_BENCHMARK_WARMUP_STEPS="$warmup_steps" \
            HELIX_BENCHMARK_STEADY_STEPS="$steady_steps" \
            HELIX_BENCHMARK_CAPTURE_CALIBRATION=0 \
            HELIX_BENCHMARK_COLLECT_BACKEND_PROFILING="$collect_backend_profiling" \
            HELIX_CUSPARSE_REUSE_PLAN="$reuse_plan" \
            HELIX_BENCHMARK_GIT_COMMIT="$head" \
            HELIX_BENCHMARK_GIT_DIRTY="$git_dirty" \
            HELIX_BENCHMARK_HOST_RUNNER="t11_ablation/$variant_id" \
            "$benchmark" > "$run_dir/stdout.jsonl" 2> "$run_dir/stderr.log"
        [[ -s "$run_dir/helix_benchmark.jsonl" ]] || die "missing benchmark JSONL for $variant_id $run_name"
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

run_benchmark_variant "A0-pre-harness" "A0" "pre harness" "$pre_ref" "$pre_worktree" "$pre_build" "clean_worktree" "pure_timing" "0" "1" "Harness-backported v0.0.3 baseline."
run_benchmark_variant "A1-post-pure-timing" "A1" "post pure timing" "$post_ref" "$post_worktree" "$post_build" "$post_ref_status" "pure_timing" "0" "1" "Post baseline with backend profiling counters disabled."
run_benchmark_variant "A2-post-attribution" "A2" "post attribution" "$post_ref" "$post_worktree" "$post_build" "$post_ref_status" "attribution" "1" "1" "Post attribution mode with backend counters enabled."
run_benchmark_variant "A3-post-legacy-wrapper-fallback" "A3" "post legacy wrapper fallback" "$post_ref" "$post_worktree" "$post_build" "$post_ref_status" "pure_timing" "0" "0" "Post pure timing with HELIX_CUSPARSE_REUSE_PLAN=0."

python3 - "$artifact_root" "$report_path" "$runs" "$warmup_steps" "$steady_steps" <<'PY'
import json
import math
import statistics
import sys
from pathlib import Path

artifact_root = Path(sys.argv[1])
report_path = Path(sys.argv[2])
runs_requested = int(sys.argv[3])
warmup_steps = int(sys.argv[4])
steady_steps = int(sys.argv[5])

variant_order = [
    "A0-pre-harness",
    "A1-post-pure-timing",
    "A2-post-attribution",
    "A3-post-legacy-wrapper-fallback",
]

def read_text(path, default=""):
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return default

def read_records(label):
    path = artifact_root / "raw" / label / "helix_benchmark.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

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

def stats(values):
    finite = []
    for value in values:
        if value is None:
            continue
        numeric = float(value)
        if math.isfinite(numeric):
            finite.append(numeric)
    if not finite:
        return {"count": 0, "median": None, "min": None, "max": None, "stdev": None}
    return {
        "count": len(finite),
        "median": statistics.median(finite),
        "min": min(finite),
        "max": max(finite),
        "stdev": statistics.stdev(finite) if len(finite) > 1 else 0.0,
    }

def steady_ms_per_step(record):
    steady = numeric_nested(record, "timing_ms", "steady_propagation")
    steps = numeric_nested(record, "problem", "steady_steps")
    if steady is None or steps is None or steps <= 0:
        return None
    return steady / steps

def main_total_ms(record):
    timing = record.get("timing_ms", {})
    values = [timing.get(name) for name in ("init", "warmup", "steady_propagation", "result_extraction", "teardown")]
    if not all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in values):
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
        return "not_available"
    if abs(value) >= 1000:
        return f"{value:.3f}"
    return f"{value:.6g}"

def ratio(numerator, denominator):
    if numerator is None or denominator is None or denominator == 0:
        return None
    return numerator / denominator

def relative_noise(summary):
    if summary["median"] in (None, 0) or summary["stdev"] is None:
        return None
    return abs(summary["stdev"] / summary["median"])

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

variants = {}
for label in variant_order:
    raw = artifact_root / "raw" / label
    records = read_records(label)
    observed_timing_modes = sorted({
        nested(record, "profiling", "timing_mode")
        for record in records
        if nested(record, "profiling", "timing_mode") is not None
    })
    variants[label] = {
        "variant_id": read_text(raw / "variant_id.txt"),
        "variant_name": read_text(raw / "variant_name.txt"),
        "description": read_text(raw / "description.txt"),
        "requested_ref": read_text(raw / "requested_ref.txt"),
        "resolved_head": read_text(raw / "git_rev.txt"),
        "ref_status": read_text(raw / "ref_status.txt"),
        "requested_timing_mode": read_text(raw / "timing_mode.txt"),
        "observed_timing_modes": observed_timing_modes,
        "collect_backend_profiling": read_text(raw / "collect_backend_profiling.txt"),
        "cusparse_reuse_plan": read_text(raw / "cusparse_reuse_plan.txt"),
        "build_type": read_text(raw / "build_type.txt"),
        "cuda_architectures": read_text(raw / "cuda_architectures.txt"),
        "warmup_steps": int(read_text(raw / "warmup_steps.txt", str(warmup_steps))),
        "steady_steps": int(read_text(raw / "steady_steps.txt", str(steady_steps))),
        "jsonl": str(raw / "helix_benchmark.jsonl"),
        "runs_recorded": len(records),
        "metrics": {metric: stats(metric_values(records, metric)) for metric, _ in metrics},
        "counters": {metric: stats(metric_values(records, metric)) for metric, _ in counters},
    }

manifest = {
    "artifact_root": str(artifact_root),
    "runs_requested": runs_requested,
    "warmup_steps": warmup_steps,
    "steady_steps": steady_steps,
    "variant_order": variant_order,
    "variants": variants,
    "source_patch_variants": {
        "A4": {
            "name": "post copy recurrence variant",
            "status": "not_run",
            "reason": "source-patch variant not automated by this clean worktree harness; run a 3-run scout if A0-A3 are inconclusive",
        },
        "A5": {
            "name": "post H old-path variant",
            "status": "not_run",
            "reason": "source-patch variant not automated by this clean worktree harness; run a 3-run scout if A0-A3 are inconclusive",
        },
    },
}
(artifact_root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

def metric_median(label, metric):
    return variants[label]["metrics"][metric]["median"]

steady_a0 = metric_median("A0-pre-harness", "steady_propagation_ms_per_step")
steady_a1 = metric_median("A1-post-pure-timing", "steady_propagation_ms_per_step")
steady_a2 = metric_median("A2-post-attribution", "steady_propagation_ms_per_step")
steady_a3 = metric_median("A3-post-legacy-wrapper-fallback", "steady_propagation_ms_per_step")
extract_a0 = metric_median("A0-pre-harness", "result_extraction_total_ms")
extract_a1 = metric_median("A1-post-pure-timing", "result_extraction_total_ms")

post_pre = ratio(steady_a1, steady_a0)
instrumentation_overhead = ratio(steady_a2, steady_a1)
reuse_off_on = ratio(steady_a3, steady_a1)
reuse_on_off = ratio(steady_a1, steady_a3)
extraction_post_pre = ratio(extract_a1, extract_a0)

ratio_rows = [
    ("A1/A0", "post/pre pure timing", post_pre, "Canonical fairness boundary for overall regression."),
    ("A2/A1", "attribution overhead", instrumentation_overhead, "Backend counter instrumentation overhead."),
    ("A3/A1", "legacy wrapper fallback / reusable plan", reuse_off_on, "Reusable plan off/on wall-clock ratio."),
    ("A1/A3", "reusable plan / legacy wrapper fallback", reuse_on_off, "Reusable plan on/off wall-clock ratio."),
    ("A1/A0 extraction", "result extraction post/pre", extraction_post_pre, "Result extraction is unlikely if near 1.0."),
]

primary = []
secondary = []
unlikely = []

def add_rank(bucket, name, evidence, action):
    bucket.append((name, evidence, action))

if instrumentation_overhead is not None and instrumentation_overhead > 1.05:
    add_rank(primary, "benchmark attribution overhead", f"A2/A1 steady ratio={fmt(instrumentation_overhead)} > 1.05", "Keep release-performance runs in pure_timing mode; use attribution only for diagnosis.")
else:
    add_rank(unlikely, "benchmark attribution overhead", f"A2/A1 steady ratio={fmt(instrumentation_overhead)}", "No T12 hot-path rollback is justified by attribution overhead alone.")

if reuse_on_off is not None and reuse_on_off > 1.10:
    add_rank(primary, "reusable cuSPARSE plan", f"A1/A3 steady ratio={fmt(reuse_on_off)} > 1.10", "T12 should fix plan pointer/update overhead or rollback by defaulting HELIX_CUSPARSE_REUSE_PLAN=0.")
elif reuse_off_on is not None and reuse_off_on < 0.90:
    add_rank(primary, "reusable cuSPARSE plan", f"A3/A1 steady ratio={fmt(reuse_off_on)} < 0.90", "T12 should fix plan pointer/update overhead or rollback by defaulting HELIX_CUSPARSE_REUSE_PLAN=0.")
else:
    add_rank(unlikely, "reusable cuSPARSE plan", f"A3/A1 steady ratio={fmt(reuse_off_on)}, A1/A3={fmt(reuse_on_off)}", "Plan on/off is not a primary culprit under the configured threshold.")

if extraction_post_pre is not None and extraction_post_pre <= 1.10:
    add_rank(unlikely, "result extraction", f"A1/A0 extraction ratio={fmt(extraction_post_pre)} <= 1.10", "Do not prioritize result extraction in T12.")
else:
    add_rank(secondary, "result extraction", f"A1/A0 extraction ratio={fmt(extraction_post_pre)}", "Inspect extraction only if hot-path candidates do not explain the regression.")

if post_pre is not None and post_pre > 1.10 and not primary:
    add_rank(primary, "unresolved source hot path", f"A1/A0 steady ratio={fmt(post_pre)} > 1.10 but A0-A3 did not isolate instrumentation or plan reuse", "Run A4/A5 3-run source-patch scouts before choosing a T12 rollback.")
elif post_pre is not None and post_pre > 1.10:
    add_rank(secondary, "source-patch variants A4/A5", f"A1/A0 steady ratio={fmt(post_pre)} remains above the recovery line", "Use A4/A5 scouts if the primary candidate fix does not recover canonical timing.")

if post_pre is None:
    verdict = "inconclusive"
elif post_pre <= 1.05:
    verdict = "within_noise_or_recovered"
elif post_pre <= 1.10:
    verdict = "partially_recovered"
else:
    verdict = "regressed"

primary_names = {name for name, _, _ in primary}
if "reusable cuSPARSE plan" in primary_names:
    t12_action = "fix_or_rollback_reusable_plan"
elif "benchmark attribution overhead" in primary_names:
    t12_action = "keep_pure_timing_release_boundary"
elif verdict == "regressed":
    t12_action = "run_A4_A5_scout_then_fix_or_rollback_selected_hot_path"
else:
    t12_action = "retain_hot_path_and_continue_recovery_sequence"

lines = []
lines.append("# T11 benchmark fairness ablation report")
lines.append("")
lines.append("This report separates pure wall-clock timing from backend attribution counters and records the minimum A0-A3 ablation matrix.")
lines.append("")
lines.append("## Verdict")
lines.append("")
lines.append(f"- Verdict: `{verdict}`")
lines.append(f"- T12 recommended action: `{t12_action}`")
lines.append(f"- Canonical A1/A0 steady ratio: `{fmt(post_pre)}`")
lines.append(f"- Instrumentation A2/A1 steady ratio: `{fmt(instrumentation_overhead)}`")
lines.append(f"- Reusable plan A1/A3 steady ratio: `{fmt(reuse_on_off)}`")
if any(variants[label]["ref_status"] != "clean_worktree" for label in variant_order):
    lines.append("- Caveat: at least one variant used a dirty post snapshot; treat this report as exploratory until rerun on clean refs.")
if any(variants[label]["runs_recorded"] < 10 for label in variant_order):
    lines.append("- Caveat: fewer than 10 recorded runs were collected for at least one A0-A3 variant.")
lines.append("")
lines.append("## Variant Matrix")
lines.append("")
lines.append("| Variant | Role | Ref | Ref status | Requested timing mode | Observed timing mode | Profiling env | Reuse plan | Runs | JSONL |")
lines.append("| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |")
for label in variant_order:
    meta = variants[label]
    observed = ",".join(meta["observed_timing_modes"]) if meta["observed_timing_modes"] else "not_available_in_ref"
    lines.append(f"| {meta['variant_id']} | {meta['variant_name']} | `{meta['requested_ref']}` | `{meta['ref_status']}` | `{meta['requested_timing_mode']}` | `{observed}` | `{meta['collect_backend_profiling']}` | `{meta['cusparse_reuse_plan']}` | {meta['runs_recorded']} | `{meta['jsonl']}` |")
lines.append("")
lines.append("## Timing Metrics")
lines.append("")
lines.append("| Variant | Metric | Meaning | Median | Min | Max | Stdev | Relative stdev |")
lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |")
for label in variant_order:
    meta = variants[label]
    for metric, meaning in metrics:
        summary = meta["metrics"][metric]
        lines.append(f"| {meta['variant_id']} | `{metric}` | {meaning} | {fmt(summary['median'])} | {fmt(summary['min'])} | {fmt(summary['max'])} | {fmt(summary['stdev'])} | {fmt(relative_noise(summary))} |")
lines.append("")
lines.append("## Ratio Summary")
lines.append("")
lines.append("| Ratio | Meaning | Value | Interpretation |")
lines.append("| --- | --- | ---: | --- |")
for name, meaning, value, interpretation in ratio_rows:
    lines.append(f"| `{name}` | {meaning} | {fmt(value)} | {interpretation} |")
lines.append("")
lines.append("## Counter Attribution")
lines.append("")
lines.append("A2 is the attribution run. Pure timing variants intentionally report `not_collected` for backend counters.")
lines.append("")
lines.append("| Variant | Counter | Meaning | Median |")
lines.append("| --- | --- | --- | ---: |")
for label in variant_order:
    meta = variants[label]
    for metric, meaning in counters:
        summary = meta["counters"][metric]
        lines.append(f"| {meta['variant_id']} | `{metric}` | {meaning} | {fmt(summary['median'])} |")
lines.append("")
lines.append("## Source-Patch Variants")
lines.append("")
lines.append("| Variant | Status | Reason | T12 use |")
lines.append("| --- | --- | --- | --- |")
for variant_id, meta in manifest["source_patch_variants"].items():
    lines.append(f"| {variant_id} {meta['name']} | `{meta['status']}` | {meta['reason']} | Run a 3-run scout before T12 if A0-A3 evidence is inconclusive or mixed. |")
lines.append("")
lines.append("## Root Cause Candidates")
lines.append("")
for title, bucket in (("Primary", primary), ("Secondary", secondary), ("Unlikely", unlikely)):
    lines.append(f"### {title}")
    lines.append("")
    if not bucket:
        lines.append("- None.")
    else:
        for name, evidence, action in bucket:
            lines.append(f"- `{name}`: {evidence}. {action}")
    lines.append("")
lines.append("## Raw Artifacts")
lines.append("")
lines.append(f"- Artifact root: `{artifact_root}`")
lines.append(f"- Manifest: `{artifact_root / 'manifest.json'}`")
lines.append(f"- GPU snapshot: `{artifact_root / 'nvidia-smi.txt'}`")
lines.append(f"- Logs: `{artifact_root / 'logs'}`")
for label in variant_order:
    meta = variants[label]
    lines.append(f"- {meta['variant_id']} JSONL: `{meta['jsonl']}`")
lines.append("")
lines.append("## Rerun Conditions")
lines.append("")
lines.append("- Use clean committed refs for `--pre-ref` and `--post-ref` before claiming final release performance.")
lines.append("- Use at least `--runs 10 --warmup-steps 10 --steady-steps 200` for canonical T11 evidence.")
lines.append("- Keep build type, CUDA architecture, GPU, CUDA runtime, and driver identical across variants.")
lines.append("- Use A2 only for attribution; do not mix attribution timing into release-performance conclusions.")
lines.append("")

report = "\n".join(lines)
(artifact_root / "t11-ablation-report.md").write_text(report, encoding="utf-8")
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(report, encoding="utf-8")
PY

log "T11 ablation benchmark complete"
log "artifact root: $artifact_root"
log "report: $report_path"
