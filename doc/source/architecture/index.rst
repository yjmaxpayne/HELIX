Architecture
============

HELIX keeps the legacy executable behavior intact while carving out tested
boundaries for reusable runtime work. It is a controlled modernization of global
CUDA state, not a clean library design yet.

Build targets
-------------

The CMake target graph has three production targets:

.. code-block:: text

   helix_host_core
     src/parameters.cu
     src/psd/eigenvalues.cu
     src/psd/psd.cu

   helix_core
     include/helix/*.h
     src/helix.cpp
     src/library/legacy_runtime_session.cu
     src/parameters.cu
     src/psd/eigenvalues.cu
     src/psd/psd.cu
     src/initialize.cu
     src/liouville.cu
     src/matrix_storage.cu
     src/matrix_util.cu
     exported as HELIX::helix
     links CUDA::cublas, CUDA::cusparse

   helix
     src/main.cu
     links helix_core, CUDA::cublas, CUDA::cusparse

``helix_host_core`` owns host-side helpers and reference logic that can be used
by unit tests without linking cuBLAS or cuSPARSE. ``helix_core`` owns the
installable C++ library target and the public ``HELIX::helix`` alias while still
wrapping the legacy CUDA runtime internally. The executable owns CLI
compatibility and legacy file output.

Runtime flow
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

Numerical profile
-----------------

The default compiled profile is defined in ``src/legacy_compile_options.h``:

* ``H_DIAGONAL`` is enabled.
* ``USE_COUNTER`` is enabled.
* ``SINGLE`` precision is enabled.
* ``DYNAMIC_DENSE`` is disabled.

The default static parameters include ``Param::N=1024``, ``Param::KMax=2``,
``Param::JMax=3``, and a default hierarchy size of 10. The checked-in baseline
``examples/outputEnergy.txt`` corresponds to ``HELIX_STEPS=1980`` and contains
1981 rows; the default full verification gate compares the
``HELIX_STEPS=1000`` prefix.

State ownership
---------------

The current runtime uses explicit global state:

* ``matrix_storage.*`` owns global device vectors such as ``dH``, ``dV``, ``dNu``,
  ``dRho``, hierarchy storage, sparse operator storage, and
  ``clearMatrixStorage()``.
* ``liouville.cu`` owns sparse propagation caches, CUDA streams, cuBLAS handles,
  cuSPARSE handles, the matrix descriptor, and ``clearLiouvilleStorage()``.
* ``parameters.*`` owns static default parameters and the global
  ``cublasHandle``.

Cleanup is part of the runtime contract. Tests and integrations that call
``initialize()`` and ``develop()`` in-process must also clear Liouville storage,
clear matrix storage, and destroy ``cublasHandle`` when they are done.

GPU execution
-------------

The default propagation path is sparse and host-orchestrated. It uses cuSPARSE
for sparse-dense products, cuBLAS for dense vector operations, CUDA streams per
hierarchy row, and a CUDA 13 compatibility wrapper in ``cuda_types.h`` for the
removed legacy ``cusparseCcsrmm`` and ``cusparseCcsrmm2`` entry points.

The old dynamic dense path remains guarded behind ``DYNAMIC_DENSE`` and should
not be treated as the active supported path unless it is explicitly restored and
verified.

Library boundary direction
--------------------------

The next step is replacing implicit global lifecycle with an explicit HEOM
context or facade. Until that boundary exists, the executable remains the
regression harness and public behavior contract.
