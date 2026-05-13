============
Benchmarking
============

HELIX benchmark artifacts are development and release-reporting evidence. They
explain performance trends and provide input for backend design work, but they
do not replace correctness, numerical, or baseline gates.

Manual command
--------------

Run benchmarks explicitly with the ``benchmark`` label:

.. code-block:: bash

   HELIX_BENCHMARK_OUTPUT_DIR="$(mktemp -d)" \
     ctest --test-dir build/cmake -L benchmark --output-on-failure

If ``HELIX_BENCHMARK_OUTPUT_DIR`` is unset or empty, the runner writes to the
configured build tree's ``benchmark/`` directory. A run creates this artifact
layout:

.. code-block:: text

   ${HELIX_BENCHMARK_OUTPUT_DIR:-<build-dir>/benchmark}/
   ├── helix_benchmark.jsonl
   ├── helix_benchmark_summary.md
   └── nsight/

The runner prints ``benchmark_artifact_root: <path>`` before execution. Upload
that artifact root for manual or scheduled benchmark workflows. Do not mix
these files into ordinary CUDA correctness logs.

CTest label boundary
--------------------

GPU benchmark tests are registered through ``helix_add_test(... GPU ...)`` and
therefore receive ``RESOURCE_LOCK gpu``. They intentionally do not receive the
``cuda`` label, because ``cuda`` is the ordinary correctness selector.

Use this command for ordinary correctness without sanitizer or benchmark
profiles:

.. code-block:: bash

   ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"

Benchmark runs are non-blocking performance measurements by default. The
current benchmark contract has no speed threshold; timing changes should be
interpreted as trend evidence for later backend design, not as automatic
correctness failures.

JSONL schema
------------

``helix_benchmark.jsonl`` is newline-delimited JSON. Each line is one
``helix.benchmark.v1`` record emitted and validated by the internal benchmark
schema helper.

Important fields:

.. list-table::
   :header-rows: 1

   * - Field
     - Meaning
   * - ``schema_version``
     - Must be ``helix.benchmark.v1``.
   * - ``run_id`` / ``timestamp_utc``
     - Stable run identifier and UTC capture time.
   * - ``helix``
     - HELIX version, version source, git commit, and optional dirty state.
   * - ``build``
     - Build type, CUDA architectures, and compiler string.
   * - ``gpu`` / ``cuda``
     - GPU name/device/memory plus CUDA runtime and driver versions.
   * - ``case``
     - Benchmark case name, backend, precision, and result mode.
   * - ``problem``
     - ``N``, ``KMax``, ``JMax``, hierarchy size, time step, integration order,
       warmup steps, steady steps, and total steps.
   * - ``timing_ms``
     - Init, warmup, steady propagation, result extraction, and teardown
       timings in milliseconds.
   * - ``memory``
     - Peak device bytes, delta bytes, and measurement method.
   * - ``gates``
     - Correctness and baseline status as ``not_run``, ``passed``, or
       ``failed``. Benchmark-only runs default to ``not_run``.
   * - ``profiling``
     - Instrumentation list, NVTX flag, optional Nsight artifact, and
       hypothesis evidence slots.

Minimal sample:

.. code-block:: json

   {
     "schema_version": "helix.benchmark.v1",
     "run_id": "20260513T000000Z-legacy-spin-glass-sm89",
     "helix": {"version": "v0.0.3", "git_commit": "unknown", "git_dirty": null},
     "build": {"type": "Release", "cuda_architectures": "89"},
     "gpu": {"name": "NVIDIA GPU", "driver": "13.0", "memory_total_bytes": 0},
     "case": {"name": "legacy_spin_glass_default", "backend": "LegacyCudaSparse", "precision": "single"},
     "problem": {"N": 1024, "KMax": 2, "JMax": 3, "hierarchy_size": 10, "steps": 2},
     "timing_ms": {"init": 0.0, "warmup": 0.0, "steady_propagation": 0.0, "result_extraction": 0.0, "teardown": 0.0},
     "memory": {"peak_device_bytes": 0, "device_delta_bytes": 0, "measurement_method": "cudaMemGetInfo_delta"},
     "gates": {"correctness_gate_status": "not_run", "baseline_gate_status": "not_run"},
     "profiling": {"instrumentation": ["runner_wall_clock"], "nvtx_enabled": false}
   }

Markdown summary
----------------

``helix_benchmark_summary.md`` is the human-readable handoff generated beside
the JSONL file. It contains:

* schema version and artifact paths;
* run metadata, including version, commit, dirty state, build type, CUDA
  architecture, GPU, driver, and runtime;
* ``legacy_spin_glass_default`` case metadata, including backend, precision,
  ``N``, ``KMax``, ``JMax``, hierarchy size, and steps;
* timing and memory tables;
* correctness and baseline gate status;
* profiling evidence slots for H-001..H-005; and
* a release/PR snippet template.

Release/report handoff
----------------------

Use the generated summary snippet in release notes or PR descriptions. The
handoff should state the environment, case, phase timings, memory metrics,
H-001..H-005 status, and gate status. For final sprint evidence, point to
``.plan/v0.0.3-helix_backend_profiling_benchmark-plan/10-final-baseline-handoff.md``
or to the uploaded benchmark artifact root.

Baseline separation
-------------------

``examples/outputEnergy.txt`` is the checked-in numerical baseline fixture for
the legacy CLI path. Benchmark JSONL and Markdown summaries are separate
performance/profiling artifacts and must not be used as a substitute for
``ctest`` correctness selectors or ``scripts/verify_examples.sh`` baseline
checks.
