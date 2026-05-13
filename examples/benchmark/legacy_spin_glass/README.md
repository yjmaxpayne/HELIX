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

Use Nsight Systems when `nsys` is available:

```sh
HELIX_BENCHMARK_WITH_NSIGHT=systems \
  examples/benchmark/legacy_spin_glass/run.sh
```

The Nsight run writes `nsight/<run_id>-systems.nsys-rep` under the artifact root
and records that relative path in `profiling.nsight_artifact`.

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
running the benchmark locally. It also includes `test_results/` with the
ordinary correctness, explicit benchmark, quick baseline, full baseline,
Python-smoke status, and Nsight-capture evidence that justify the sample's gate
status fields. Timing values are machine-dependent.
