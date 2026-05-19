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

User-facing example
-------------------

The same benchmark can be run through a repository example:

.. code-block:: bash

   examples/benchmark/legacy_spin_glass/run.sh

The example writes artifacts to
``build/cmake/example-benchmark/legacy_spin_glass/`` by default. A checked-in
sample result lives in ``examples/benchmark/legacy_spin_glass/reference/`` and
includes ``helix_benchmark.jsonl`` and ``helix_benchmark_summary.md``. Raw
Nsight reports are intentionally excluded because profiler captures can embed
environment variables, credentials, and local paths. Its ``test_results/``
subdirectory records the ordinary correctness, explicit benchmark, quick/full
baseline, Python-smoke status, and Nsight tool checks from the same validation
session. Treat those files as format examples; timing values are
machine-dependent.

Optional Nsight capture
-----------------------

Nsight capture is an optional local profiling path. It requires NVIDIA Nsight
Systems and Nsight Compute on the machine running the benchmark; these tools
are not ordinary CI dependencies. Capture failures do not fail ordinary
correctness CI, and HELIX does not install or run Nsight capture in the default
CUDA correctness path.

Build the default benchmark executable before capture:

.. code-block:: bash

   cmake --build build/cmake --target legacy_spin_glass_benchmark --parallel "$(nproc)"

Use the benchmark artifact root and write reports under its ``nsight/``
subdirectory. Start manual captures from an environment without API keys,
tokens, secrets, passwords, or credential paths because Nsight reports may
record the profiled process environment:

.. code-block:: bash

   export HELIX_BENCHMARK_OUTPUT_DIR="${HELIX_BENCHMARK_OUTPUT_DIR:-$(pwd)/build/cmake/benchmark}"
   run_id="$(date -u +%Y%m%dT%H%M%SZ)-legacy-spin-glass"
   mkdir -p "${HELIX_BENCHMARK_OUTPUT_DIR}/nsight"

   nsys profile \
     --force-overwrite true \
     --trace=cuda,nvtx,osrt \
     --output "${HELIX_BENCHMARK_OUTPUT_DIR}/nsight/${run_id}-systems" \
     build/cmake/legacy_spin_glass_benchmark

   ncu \
     --force-overwrite \
     --target-processes all \
     --set full \
     --export "${HELIX_BENCHMARK_OUTPUT_DIR}/nsight/${run_id}-compute" \
     build/cmake/legacy_spin_glass_benchmark

The artifact convention is ``nsight/<run_id>-systems.*`` for Nsight Systems
and ``nsight/<run_id>-compute.*`` for Nsight Compute. The benchmark JSONL
field ``profiling.nsight_artifact`` is ``null`` when no capture is collected;
the generated Markdown summary renders the same state as ``not_collected``.
When using the example wrapper, set ``HELIX_BENCHMARK_WITH_NSIGHT=systems``;
the wrapper sets ``HELIX_BENCHMARK_NSIGHT_ARTIFACT`` so the generated JSONL and
summary record ``nsight/<run_id>-systems.nsys-rep``. The wrapper removes
environment variables whose names contain ``KEY``, ``TOKEN``, ``SECRET``,
``PASSWORD``, or ``CREDENTIAL`` before launching Nsight.
If correctness or baseline gates were run separately in the same validation
session, set ``HELIX_BENCHMARK_CORRECTNESS_GATE_STATUS=passed|failed`` and
``HELIX_BENCHMARK_BASELINE_GATE_STATUS=passed|failed`` before invoking the
benchmark. Standalone benchmark runs should leave those fields at the default
``not_run``.
Set ``HELIX_BENCHMARK_CAPTURE_CALIBRATION=0`` for a main-only artifact, or use
the default ``1`` to run the separate HEOMSolver calibration cross-check.
Calibration is always recorded as a separate scope and is excluded from main
timing aggregation.
Set ``HELIX_CUSPARSE_REUSE_PLAN=0`` only for rollback triage; it disables the
reusable cuSPARSE backend plan and routes sparse calls through the legacy
``cuda_types.h`` compatibility wrappers, reintroducing per-call wrapper setup.

Suggested NVTX markers
----------------------

The current benchmark does not require NVTX markers. Benchmark artifacts
nevertheless record this scope naming convention for future opt-in captures:
``benchmark.main.init``, ``benchmark.main.warmup``,
``benchmark.main.steady_propagation``, ``benchmark.main.result_extraction``,
``benchmark.main.teardown``, and ``benchmark.calibration``.

If internal markers are added in a future opt-in build or run mode, reuse these
names instead of creating a parallel naming scheme:

.. list-table::
   :header-rows: 1

   * - Marker
     - Suggested source location
     - Evidence mapping
   * - ``helix.develop``
     - ``src/liouville.cu`` ``develop()``
     - H-003 steady propagation and synchronization boundaries.
   * - ``helix.getdRhoSparse``
     - ``src/liouville.cu`` ``getdRhoSparse()``
     - H-001 sparse descriptor/workspace cost and H-003 propagation timing.
   * - ``helix.cuda_sparse_backend_plan``
     - ``src/cuda_sparse_backend_plan.cu`` ``CudaSparseBackendPlan::run()``
     - H-001 descriptor/workspace rebuild cost and H-004 handle/stream cost.
   * - ``helix.transpose``
     - ``src/matrix_util.cu`` ``transpose()`` and sparse call sites in
       ``src/liouville.cu``
     - Deferred H-005 transpose/layout hotspot evidence.
   * - ``helix.integrator_d2d``
     - ``src/liouville.cu`` ``develop()``
     - H-005 integrator D2D copy count and byte evidence.
   * - ``helix.result_extraction``
     - ``src/library/result_extractor.cu`` ``ResultExtractor::final_reduced_density()``
     - H-002 host copy and result extraction cost.

Manual or scheduled Nsight workflows must use ``workflow_dispatch`` or a
scheduled trigger only. They must not be added to the pull-request required
path. Raw profiler reports must not be committed; if they are uploaded for
internal review, keep them in an access-controlled benchmark artifact root
rather than baseline output paths.

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

v0.0.5 CUDA Graph spike gate
----------------------------

``v005_cuda_graph_spike_gate`` registers the
``legacy_spin_glass_graph_spike`` binary
(``tests/benchmark/legacy_spin_glass_graph_spike.cu``) under label
``benchmark`` with ``RESOURCE_LOCK gpu``. It captures a fixed-shape
``develop()`` trace through ``cudaStreamBeginCapture`` and replays it as a
CUDA Graph to collect the M2 capture-feasibility evidence required by the
v0.0.5 stream-aware execution plan. The keep-state contract with
``HELIX_DEBUG_SYNC_MODE`` unset (off) is ``verdict=captured`` and
``graph_non_null=true``; the gate explicitly depends on the env var being
off because additive ``cudaDeviceSynchronize()`` is forbidden inside
``cudaStreamBeginCapture``.

The gate is excluded from the default selector
``ctest -LE "^(sanitizer|benchmark)$"``. Invoke it explicitly with
``ctest -L benchmark`` (or by name with ``-R v005_cuda_graph_spike_gate``)
and leave ``HELIX_DEBUG_SYNC_MODE`` unset.

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
   * - ``measurement_scope``
     - Main/calibration scope names, capture state, calibration exclusion from
       main aggregation, and the NVTX naming convention.
   * - ``memory``
     - Peak device bytes, delta bytes, and measurement method.
   * - ``gates``
     - Correctness and baseline status as ``not_run``, ``passed``, or
       ``failed``. Benchmark-only runs default to ``not_run``.
   * - ``profiling``
     - Instrumentation list, NVTX flag, optional Nsight artifact, and
       hypothesis evidence slots. The generated Markdown summary also records
       the ``H_DIAGONAL`` elementwise specialization comparison; the default
       steady benchmark expects V-path-only SpMM calls after the diagonal
       Hamiltonian term leaves the cuSPARSE path. It also records the
       structured ``V`` specialization decision, the generic sparse contract
       boundary, the T8 synchronization audit, and the fixed-shape CUDA Graph
       feasibility decision.

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
     "measurement_scope": {
       "main_measurement_scope": "benchmark.main",
       "main_measurement_status": "captured",
       "calibration_scope": "benchmark.calibration",
       "calibration_status": "captured",
       "calibration_captured": true,
       "calibration_excluded_from_main": true,
       "nvtx_naming_convention": "benchmark.main.init,benchmark.main.warmup,benchmark.main.steady_propagation,benchmark.main.result_extraction,benchmark.main.teardown,benchmark.calibration"
     },
     "memory": {"peak_device_bytes": 0, "device_delta_bytes": 0, "measurement_method": "cudaMemGetInfo_delta"},
     "gates": {"correctness_gate_status": "not_run", "baseline_gate_status": "not_run"},
     "profiling": {
       "instrumentation": ["runner_wall_clock", "cudaDeviceSynchronize_phase_boundaries"],
       "nvtx_enabled": false,
       "nsight_artifact": null,
       "counters": {
         "spmm": {
           "call_count": 320,
           "descriptor_create_count": 0,
           "workspace_alloc_count": 0,
           "workspace_bytes": 183,
           "buffer_size_query_count": 0
         },
         "transpose": {
           "call_count": 320,
           "time_ms": "not_collected",
           "bytes": 2684354560
         },
         "d2d_copy": {
           "copy_count": 2,
           "time_ms": "not_collected",
           "bytes": 167772160
         },
         "sync": {
           "device_synchronize_count": 1,
           "sync_wait_ms": 0.0
         },
         "result_extraction": {
           "sync_wait_ms": 0.0,
           "host_allocation_ms": 0.0,
           "d2h_copy_ms": 0.0,
           "conversion_ms": 0.0,
           "d2h_bytes": 8388608,
           "element_count": 1048576
         }
       },
       "hypotheses": [
         {
           "id": "H-001",
           "name": "descriptor/workspace rebuild cost",
           "status": "collected",
           "fields": [{"name": "spmm_call_count", "value": "320", "unit": "count"}],
           "method": "private CudaSparseBackendPlan SpMM counters captured in the steady propagation scope after warmup",
           "interpretation": "Descriptor creation, workspace allocation, buffer-size query, and SpMM call counters are separated from aggregate timing; warmed compatible calls should report zero setup counters.",
           "downstream_action": "Use these counters to gate downstream H-diagonal, D2D traffic, layout, and graph feasibility tasks."
         }
       ]
     }
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
* timing, measurement scope, memory, and profiling counter tables;
* CUDA 13 cuSPARSE API adopt/defer/reject decision table;
* structural legacy-wrapper versus reusable-plan SpMM setup comparison;
* ``H_DIAGONAL`` elementwise specialization comparison;
* structured ``V`` specialization decision for the legacy spin-glass path;
* integrator D2D recurrence before/after comparison;
* layout/transpose option matrix with the public row-major result-order statement;
* synchronization audit with the landed per-stream event pool and
  fan-in/fan-out rendezvous in ``liouville.cu``
  (``sparseStreamEvents`` / ``sparseRendezvousEvent`` /
  ``developStreamEvent``);
* fixed-shape CUDA Graph feasibility decision;
* correctness and baseline gate status;
* structured profiling evidence slots for H-001..H-005; and
* a release/PR snippet template.

Each hypothesis entry records ``id``, ``name``, ``status``, ``fields``,
``method``, ``interpretation``, and ``downstream_action``. Allowed evidence
statuses are ``not_collected``, ``collected``, ``inconclusive``, ``supported``,
and ``not_supported``. Missing counters must be recorded as ``not_collected``
rather than left blank.

Release/report handoff
----------------------

Use the generated summary snippet in release notes or PR descriptions. The
handoff should state the environment, case, phase timings, memory metrics,
H-001..H-005 status, and gate status. For final sprint evidence, point to
``.plan/v0.0.4-helix-gpu-heom-optimize-plan/10-final-benchmark-handoff.md``
or to the uploaded benchmark artifact root.

Baseline separation
-------------------

``examples/outputEnergy.txt`` is the checked-in numerical baseline fixture for
the legacy CLI path. Benchmark JSONL and Markdown summaries are separate
performance/profiling artifacts and must not be used as a substitute for
``ctest`` correctness selectors or ``scripts/verify_examples.sh`` baseline
checks.
