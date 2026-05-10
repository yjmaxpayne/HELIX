C++/CUDA Source API
===================

The C++/CUDA API pages are generated from ``include/`` and selected ``src/``
headers. They document the v0.1 public C++ foundation together with the current
implementation surface used by the executable and tests.

Architecture Mapping
--------------------

.. code-block:: text

   include/helix/               public v0.1 C++ library foundation
   ├── helix.h                  aggregate public include
   ├── types.h                  Context, HEOMSolver, System, Bath, results
   ├── examples.h               legacy spin-glass adapter declaration
   └── version.h                public version helpers

   src/                         legacy CUDA runtime and implementation details
   ├── helix.cpp                public API implementation over legacy runtime
   ├── library/                 legacy runtime session wrapper
   ├── main.cu                  executable workflow and output files
   ├── initialize.*             system, bath, hierarchy, rho initialization
   ├── initialize_detail.h      test-backed host helper extraction point
   ├── liouville.*              HEOM propagation and dRho evaluation
   ├── matrix_storage.*         global device storage lifecycle
   ├── matrix_util.*            CUDA matrix utilities
   ├── parameters.*             static defaults and global cublasHandle
   ├── cuda_types.h             scalar aliases and CUDA compatibility wrappers
   └── psd/                     Pade spectrum decomposition helpers

Conventions
-----------

* Declarations live in ``*.h`` files; implementation lives in ``*.cu`` files.
* Legacy source files use tabs for block indentation.
* Source and test file names use ``lower_snake_case``.
* Local helper functions generally use camelCase.
* ``include/helix`` is the current public C++ foundation.
* Selected ``src`` pages are implementation references, not ABI promises.

Generated Index
---------------

See :doc:`generated` for Doxygen/Breathe pages over the selected public
headers and helper namespaces.
