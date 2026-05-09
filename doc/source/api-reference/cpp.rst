C++/CUDA Source API
===================

The C++/CUDA source API is generated from ``src/``. It documents the current
implementation surface used by the executable and tests.

Architecture Mapping
--------------------

.. code-block:: text

   src/                         responsibility
   ├── Main.cu                  executable workflow and output files
   ├── Initialize.*             system, bath, hierarchy, rho initialization
   ├── InitializeDetail.h       test-backed host helper extraction point
   ├── Liouville.*              HEOM propagation and dRho evaluation
   ├── Matrixes.*               global device storage lifecycle
   ├── MatrixUtil.*             CUDA matrix utilities
   ├── Parameters.*             static defaults and global cublasHandle
   ├── TypeDef.h                scalar aliases and CUDA compatibility wrappers
   └── Psd/                     Pade spectrum decomposition helpers

Conventions
-----------

* Declarations live in ``*.h`` files; implementation lives in ``*.cu`` files.
* Legacy source files use tabs for block indentation.
* Major headers and types use PascalCase.
* Local helper functions generally use camelCase.
* Generated API pages are implementation references, not ABI promises.

Generated Index
---------------

See :doc:`generated` for Doxygen/Breathe pages over the selected public
headers and helper namespaces.
