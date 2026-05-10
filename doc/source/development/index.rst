===========
Development
===========

Contributor docs cover build commands, testing practice, numerical-change
rules, and the documentation workflow.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   build-and-test
   documentation

Overview
--------

HELIX is under active modernization. Keep changes small, preserve the current
baseline behavior unless a numerical change is intentional, and pair GPU
execution changes with targeted CTest coverage.

Project structure
-----------------

.. code-block:: text

   HELIX/
   ├── include/helix/          # Public v0.1 C++ library headers
   ├── src/                    # C++/CUDA production source
   │   ├── library/            # Legacy runtime session wrapper
   │   ├── psd/                # Pade spectrum decomposition helpers
   │   ├── helix.cpp           # Public API implementation over legacy runtime
   │   ├── main.cu             # Legacy executable workflow
   │   ├── initialize.*        # System, bath, hierarchy, rho setup
   │   ├── liouville.*         # Propagation and dRho evaluation
   │   ├── matrix_storage.*    # Global device storage lifecycle
   │   └── cuda_types.h        # Scalar aliases and CUDA wrappers
   ├── tests/                  # Unit, CUDA, numerical, integration tests
   ├── examples/               # Checked-in reference output and C++ smoke example
   ├── scripts/                # Verification and release helpers
   └── doc/                    # Sphinx documentation

Development principles
----------------------

* Preserve numerical semantics in cleanup-only changes.
* Use CTest labels and ``helix_add_test()`` for new tests.
* Keep generated run outputs out of Git.
* Document behavior from actual source, tests, and baseline fixtures.
* Prefer small Doxygen comments on declarations and longer rationale in
  narrative architecture pages.
