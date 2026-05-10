C++/CUDA Source API
===================

The C++/CUDA source API is generated from ``src/``. It documents the current
implementation surface used by the executable and tests.

Architecture Mapping
--------------------

.. code-block:: text

   src/                         responsibility
   ├── main.cu                  executable workflow and output files
   ├── initialize.*             system, bath, hierarchy, rho initialization
   ├── initialize_detail.h      test-backed host helper extraction point
   ├── liouville.*              HEOM propagation and dRho evaluation
   ├── matrix_storage.*         global device storage lifecycle
   ├── matrix_util.*             CUDA matrix utilities
   ├── parameters.*             static defaults and global cublasHandle
   ├── cuda_types.h             scalar aliases and CUDA compatibility wrappers
   └── psd/                     Pade spectrum decomposition helpers

Conventions
-----------

* Declarations live in ``*.h`` files; implementation lives in ``*.cu`` files.
* Legacy source files use tabs for block indentation.
* Source and test file names use ``lower_snake_case``.
* Local helper functions generally use camelCase.
* Generated API pages are implementation references, not ABI promises.

Generated Index
---------------

See :doc:`generated` for Doxygen/Breathe pages over the selected public
headers and helper namespaces.
