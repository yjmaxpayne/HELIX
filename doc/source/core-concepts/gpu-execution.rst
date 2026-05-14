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

CUDA 13 compatibility
---------------------

CUDA 13 removed legacy ``cusparseCcsrmm`` and ``cusparseCcsrmm2`` APIs. HELIX
keeps source compatibility through wrappers in ``cuda_types.h`` that map those
operations to ``cusparseSpMM``. The plan-enabled path adopts
``cusparseDnMatSetValues`` and one-time ``cusparseSpMM_bufferSize`` queries,
rejects values-only sparse rebinding for the current stable H/V operators, and
defers ``cusparseCsrSetPointers`` and ``cusparseSpMM_preprocess`` until dynamic
CSR/layout and CUDA Graph feasibility tasks have separate correctness gates.

Dynamic dense path
------------------

The old ``DYNAMIC_DENSE`` path remains guarded behind a macro and is not the
default supported path. Treat it as inactive unless a task explicitly restores
and verifies it.
