# Benchmark Reference Validation Results

This directory captures the full validation context for the checked-in
`examples/benchmark/legacy_spin_glass/reference/` benchmark result.

## Gate Summary

| Gate | Command | Result | Evidence |
| --- | --- | --- | --- |
| Ordinary correctness | `ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"` | Passed, 24/24, 0 failed | `ordinary_correctness_ctest.txt` |
| Explicit benchmark | `ctest --test-dir build/cmake -L benchmark --output-on-failure` | Passed, 2/2, 0 failed | `benchmark_ctest.txt` |
| Quick baseline | `HELIX_STEPS=2 scripts/verify_examples.sh` | Passed, 3 rows, `max_energy_diff=5e-07`, tolerance `1e-05` | `quick_baseline_energy_compare.txt` |
| Full baseline | `HELIX_STEPS=1980 scripts/verify_examples.sh` | Passed, 1981 rows, `max_energy_diff=4e-06`, tolerance `1e-05` | `full_baseline_energy_compare.txt` |
| Python smoke/result semantics | default `build/cmake` CTest inventory | Not run; `HELIX_BUILD_PYTHON=OFF`, `v01_python_smoke_gate` not registered | `python_smoke_status.txt` |
| Nsight tool/capture | optional local Nsight path | Not run for this T9 reference refresh; JSONL records `nsight_artifact=null` | `nsight_tool_status.txt` |

## Benchmark Artifact Alignment

The benchmark record in `../helix_benchmark.jsonl` was generated after the
ordinary correctness and 1980-step baseline gates above passed. Its gate block
therefore
records:

```json
"gates": {
  "correctness_gate_status": "passed",
  "baseline_gate_status": "passed"
}
```

Standalone benchmark runs should leave those fields as `not_run` unless the
corresponding gates were executed in the same validation session.

The T9 reference refresh also records
`structured_v_specialization_decision=defer_legacy_spin_glass_only` in H-001
profiling evidence and in `../helix_benchmark_summary.md`. This decision is
private to the legacy spin-glass path and leaves `System::from_sparse()`
validation-only semantics unchanged.
