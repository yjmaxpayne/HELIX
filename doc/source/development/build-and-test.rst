==============
Build and test
==============

Build commands
--------------

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"

Use ``-DHELIX_CUDA_ARCHITECTURES=<arch>`` when automatic GPU architecture
detection is not available.

CTest labels
------------

Register tests with ``helix_add_test()`` in ``CMakeLists.txt``. The accepted
labels are:

* ``unit``
* ``cuda``
* ``numerical``
* ``integration``
* ``baseline``
* ``sanitizer``
* ``benchmark``

GPU tests must pass the ``GPU`` option. The helper sets ``RESOURCE_LOCK gpu``
for every GPU test, adds the ``cuda`` label unless the test has a
``sanitizer`` or ``benchmark`` label, and prevents ``unit`` from being mixed
with GPU execution. ``ctest -L cuda`` is the ordinary CUDA correctness
selector; benchmark profiles must be selected explicitly.

Useful selectors:

.. code-block:: bash

   ctest --test-dir build/cmake -L unit --output-on-failure
   ctest --test-dir build/cmake -L cuda -N
   ctest --test-dir build/cmake -L numerical --output-on-failure
   ctest --test-dir build/cmake -L benchmark --output-on-failure
   ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"

Stream-aware sync microtests
----------------------------

The v0.0.5 stream-aware execution work registers two CUDA mechanism
microtests under the ordinary ``cuda`` label:

* ``develop_stream_ownership_microtests``
  (``tests/cuda/develop_stream_ownership_microtests.cu``) — exercises
  ``cudaMemcpyAsync`` D-to-D copies on an owned non-default stream and
  mirrors the M3.1 patch inside ``src/liouville.cu`` ``develop()``.
* ``event_based_sync_microtests``
  (``tests/cuda/event_based_sync_microtests.cu``) — exercises
  ``cudaEventRecord`` plus ``cudaStreamWaitEvent`` across N owned
  streams and mirrors the M3.2 helpers ``sparseStreamFanInToZero`` and
  ``sparseStreamFanOutFromZero``.

Both are GPU tests with ``RESOURCE_LOCK gpu`` and a 30 s timeout and run
inside ``ctest -L cuda``. See :doc:`../core-concepts/gpu-execution` for
the event-pool topology they target.

Benchmark artifacts
-------------------

The legacy spin-glass benchmark runner writes artifacts under
``HELIX_BENCHMARK_OUTPUT_DIR``. If the variable is unset or empty, the default
is the configured build tree's ``benchmark/`` directory. A benchmark run
produces:

* ``helix_benchmark.jsonl``
* ``helix_benchmark_summary.md``
* ``nsight/``

The runner prints ``benchmark_artifact_root: <path>`` at startup. Benchmark
artifacts are kept separate from ordinary CUDA correctness logs; manual or
scheduled benchmark workflows should use a runner-temp location such as
``${RUNNER_TEMP}/helix-benchmark`` and upload only that artifact root.
The GPU benchmark gate uses ``RESOURCE_LOCK gpu`` but is not part of the
``cuda`` correctness label. Benchmark failures report benchmark execution or
artifact problems; HELIX does not apply a default speed threshold.

``examples/outputEnergy.txt`` is the numerical baseline fixture. Benchmark
JSONL and Markdown summaries are profiling/reporting artifacts, not baseline
correctness artifacts.

Numerical changes
-----------------

Cleanup-only changes must preserve HEOM numerical semantics. For intentional
numerical changes, document the affected parameters, reference source, expected
baseline difference, and tolerance.

The default numerical profile is single precision with ``Param::N=1024``,
``Param::KMax=2``, ``Param::JMax=3``, and hierarchy size 10.

Runtime environment variables
-----------------------------

The ``helix`` executable and library reads the following runtime
environment variables. The same table lives in ``README.md`` as the
user-facing reference; this section is the developer-facing cross-link.

.. list-table::
   :header-rows: 1
   :widths: 30 12 58

   * - Variable
     - Default
     - Purpose
   * - ``HELIX_STEPS`` (alias ``HEOM_STEPS``)
     - ``1000000``
     - Override the number of integration steps for the legacy executable.
   * - ``HELIX_DEBUG_SYNC_MODE``
     - ``off``
     - Opt-in diagnostic only. When set to ``1``, ``on``, ``ON``,
       ``true``, or ``TRUE``, HELIX re-adds defensive
       ``cudaDeviceSynchronize()`` calls alongside the event-based sync
       path at four Segment-2 sites: the Taylor-loop fence in
       ``develop()``, ``getdRhoSparse``'s stage barrier,
       ``getdRhoSparse``'s exit barrier, and the per-step outer fence
       in ``LegacyRuntimeSession::run_steps()``. Intended for
       first-error attribution during the segment-2-to-segment-5
       migration. On mode intentionally blocks CUDA Graph capture
       because additive ``cudaDeviceSynchronize()`` inside
       ``cudaStreamBeginCapture`` is forbidden, so leaving the variable
       unset is required for ``v005_cuda_graph_spike_gate`` (see
       :doc:`benchmarking`).
