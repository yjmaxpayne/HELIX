# Legacy Spin-Glass Benchmark Example

This example runs the same opt-in benchmark gate used by the HELIX test suite
and writes user-facing benchmark artifacts into an isolated output directory.
Benchmark artifacts are performance/profiling evidence only; they are not a
replacement for `examples/outputEnergy.txt` numerical baseline checks.

From the repository root:

```sh
examples/benchmark/legacy_spin_glass/run.sh
```

By default the script builds `legacy_spin_glass_benchmark` in `build/cmake` and
writes artifacts to:

```text
build/cmake/example-benchmark/legacy_spin_glass/
├── helix_benchmark.jsonl
├── helix_benchmark_summary.md
└── nsight/
```

Use a custom artifact root:

```sh
HELIX_BENCHMARK_OUTPUT_DIR="$(mktemp -d)" \
  examples/benchmark/legacy_spin_glass/run.sh
```

Generate a main-only artifact without running the HEOMSolver calibration
cross-check:

```sh
HELIX_BENCHMARK_CAPTURE_CALIBRATION=0 \
  examples/benchmark/legacy_spin_glass/run.sh
```

The default is main measurement plus calibration capture:

```sh
HELIX_BENCHMARK_CAPTURE_CALIBRATION=1 \
  examples/benchmark/legacy_spin_glass/run.sh
```

In both modes the JSONL and Markdown summary record
`measurement_scope.main_measurement_scope`, `measurement_scope.calibration_scope`,
`measurement_scope.calibration_captured`, and
`measurement_scope.calibration_excluded_from_main`. Calibration timing is not
included in the main timing aggregation.

For rollback triage, set `HELIX_CUSPARSE_REUSE_PLAN=0` to disable the reusable
cuSPARSE backend plan and route sparse calls through the legacy compatibility
wrappers. Do not use that mode as the performance evidence path; it restores
per-call wrapper setup.

Use Nsight Systems when `nsys` is available:

```sh
HELIX_BENCHMARK_WITH_NSIGHT=systems \
  examples/benchmark/legacy_spin_glass/run.sh
```

The Nsight run writes `nsight/<run_id>-systems.nsys-rep` under the artifact root
and records that relative path in `profiling.nsight_artifact`. The wrapper strips
environment variables whose names look secret-like before launching Nsight, but
raw profiler reports can still contain local process metadata and must not be
committed.

If correctness or baseline gates were run separately in the same validation
session, record that context explicitly:

```sh
HELIX_BENCHMARK_CORRECTNESS_GATE_STATUS=passed \
HELIX_BENCHMARK_BASELINE_GATE_STATUS=passed \
HELIX_BENCHMARK_WITH_NSIGHT=systems \
  examples/benchmark/legacy_spin_glass/run.sh
```

The `reference/` directory contains one captured sample from the maintainer
machine so users can inspect the JSONL and Markdown summary formats before
running the benchmark locally. Raw Nsight reports are intentionally excluded
because profiler captures can embed environment variables and local paths. The
Markdown summary records the `H_DIAGONAL` elementwise specialization comparison
and the default steady SpMM count after the diagonal Hamiltonian term leaves the
cuSPARSE path. It also records the structured `V` specialization decision as
`defer_legacy_spin_glass_only`, with `System::from_sparse()` remaining
validation-only and unaffected. The directory includes `test_results/` with the
ordinary correctness, explicit benchmark, quick baseline, full baseline,
Python-smoke status, and Nsight optional-capture status that justify the
sample's gate status fields. Timing values are machine-dependent.
