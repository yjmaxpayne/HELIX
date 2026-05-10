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

CUDA 13 compatibility
---------------------

CUDA 13 removed legacy ``cusparseCcsrmm`` and ``cusparseCcsrmm2`` APIs. HELIX
keeps source compatibility through wrappers in ``cuda_types.h`` that map those
operations to ``cusparseSpMM``.

Dynamic dense path
------------------

The old ``DYNAMIC_DENSE`` path remains guarded behind a macro and is not the
default supported path. Treat it as inactive unless a task explicitly restores
and verifies it.
