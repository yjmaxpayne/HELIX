=============
GPU execution
=============

HELIX uses CUDA, cuBLAS, and cuSPARSE. The default active path is sparse and
host-orchestrated.

Sparse path
-----------

``getdRhoSparse()`` prepares per-hierarchy CUDA streams, cuBLAS handles,
cuSPARSE handles, and coefficient storage. It computes sparse Hamiltonian and
coupling contributions with cuSPARSE and accumulates dense vector operations
with cuBLAS.

The default sparse path uses a private reusable cuSPARSE backend plan for
compatible SpMM calls. The plan keeps sparse and dense descriptors plus the
SpMM workspace alive across steady propagation, updates dense input/output
pointers with ``cusparseDnMatSetValues``, and rejects shape or CSR pointer
mismatches instead of silently rebinding an incompatible operator. Set
``HELIX_CUSPARSE_REUSE_PLAN=0`` to route sparse calls through the legacy
``cuda_types.h`` compatibility wrappers for rollback triage.

The compiled diagonal-Hamiltonian path uses an elementwise kernel, so the
remaining steady-scope SpMM and physical transpose counters come from the
legacy spin-glass ``V`` path. A structured ``V`` replacement is deferred for
v0.0.4 and would be private to the legacy spin-glass adapter. It does not
change the validation-only ``System::from_sparse()`` contract or add arbitrary
sparse HEOM runtime support.

CUDA 13 compatibility
---------------------

CUDA 13 removed legacy ``cusparseCcsrmm`` and ``cusparseCcsrmm2`` APIs. HELIX
keeps source compatibility through wrappers in ``cuda_types.h`` that map those
operations to ``cusparseSpMM``. The plan-enabled path adopts
``cusparseDnMatSetValues`` and one-time ``cusparseSpMM_bufferSize`` queries,
rejects values-only sparse rebinding for the current stable H/V operators, and
defers ``cusparseCsrSetPointers`` and ``cusparseSpMM_preprocess`` until dynamic
CSR/layout and CUDA Graph feasibility tasks have separate correctness gates.

Layout and result order
-----------------------

The current backend keeps the public reduced-density buffer contract
row-major. Sparse commutator call sites may still use physical transposes to
bridge cuSPARSE descriptor order and the legacy dense buffer semantics, but
``ReducedDensityShape::storageOrder`` remains ``RowMajor`` for public
``RunResult`` values. Any future backend-local layout change must convert at
``ResultExtractor`` before crossing the public API boundary.

Synchronization and CUDA Graphs
-------------------------------

The current production path still uses device-wide synchronization as explicit
correctness, dependency, and error boundaries around ``develop()``,
``getdRhoSparse()``, ``LegacyRuntimeSession::run_steps()``, and storage teardown.
The benchmark summary records the T8 synchronization audit and marks fixed-shape
CUDA Graph capture as ``defer_fixed_shape_capture`` for v0.0.4. Any future graph
path must first replace hot-path device fences with tested stream/event
dependencies while preserving a debug sync mode for first-failure attribution.

Dynamic dense path
------------------

The old ``DYNAMIC_DENSE`` path remains guarded behind a macro and is not the
default supported path. Treat it as inactive unless a task explicitly restores
and verifies it.
