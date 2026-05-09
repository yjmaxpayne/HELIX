Architecture
============

HELIX keeps the legacy executable behavior intact while carving out tested
boundaries for a future reusable HEOM runtime. The architecture is therefore a
controlled modernization of global CUDA state, not a clean library design yet.

Build Targets
-------------

The CMake target graph has two production targets:

.. code-block:: text

   helix_host_core
     src/Parameters.cu
     src/Psd/Eigval.cu
     src/Psd/Psd.cu

   helix
     src/Main.cu
     src/Initialize.cu
     src/Liouville.cu
     src/Matrixes.cu
     src/MatrixUtil.cu
     links helix_host_core, CUDA::cublas, CUDA::cusparse

``helix_host_core`` owns host-side helpers and reference logic that can be used
by unit tests without linking cuBLAS or cuSPARSE. The executable owns CUDA
runtime execution and legacy file output.

Runtime Flow
------------

The executable follows this sequence:

.. code-block:: text

   main
     initialize
       initializePsdData
       setTemperatureDependence
       createSystem
       initializeCublas
       initializeHierarchyStorage
       initializeRhoAndBuffer
       initializeDeviceConstants
     repeat HELIX_STEPS times
       outputRho at configured intervals
       develop
     write final outputs
     clearLiouvilleStorage
     clearMatrixStorage
     destroy cublasHandle

``HELIX_STEPS`` controls the run length. ``HEOM_STEPS`` is accepted as a legacy
alias. Invalid or missing values fall back to the legacy default of 1,000,000
steps.

Numerical Profile
-----------------

The default compiled profile is defined in ``src/DefineParameters.h``:

* ``H_DIAGONAL`` is enabled.
* ``USE_COUNTER`` is enabled.
* ``SINGLE`` precision is enabled.
* ``DYNAMIC_DENSE`` is disabled.

The default static parameters include ``Param::N=1024``, ``Param::KMax=2``,
``Param::JMax=3``, and a default hierarchy size of 10. The checked-in baseline
``examples/outputEnergy.txt`` corresponds to ``HELIX_STEPS=1980`` and contains
1981 rows.

State Ownership
---------------

The current runtime uses explicit global state:

* ``Matrixes.*`` owns global device vectors such as ``dH``, ``dV``, ``dNu``,
  ``dRho``, hierarchy storage, sparse operator storage, and
  ``clearMatrixStorage()``.
* ``Liouville.cu`` owns sparse propagation caches, CUDA streams, cuBLAS handles,
  cuSPARSE handles, the matrix descriptor, and ``clearLiouvilleStorage()``.
* ``Parameters.*`` owns static default parameters and the global
  ``cublasHandle``.

Cleanup is part of the runtime contract. Tests and integrations that call
``initialize()`` and ``develop()`` in-process must also clear Liouville storage,
clear matrix storage, and destroy ``cublasHandle`` when they are done.

GPU Execution
-------------

The default propagation path is sparse and host-orchestrated. It uses cuSPARSE
for sparse-dense products, cuBLAS for dense vector operations, CUDA streams per
hierarchy row, and a CUDA 13 compatibility wrapper in ``TypeDef.h`` for the
removed legacy ``cusparseCcsrmm`` and ``cusparseCcsrmm2`` entry points.

The old dynamic dense path remains guarded behind ``DYNAMIC_DENSE`` and should
not be treated as the active supported path unless it is explicitly restored and
verified.

Library Boundary Direction
--------------------------

The next architectural pressure point is replacing implicit global lifecycle
with an explicit HEOM context or facade. Until that boundary exists, the
executable remains the authoritative regression harness and public behavior
contract.
