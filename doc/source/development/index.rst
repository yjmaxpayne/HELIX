===========
Development
===========

This section provides guidance for contributing to HELIX, including build
commands, testing practice, numerical-change rules, and documentation workflow.

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

Project Structure
-----------------

.. code-block:: text

   HELIX/
   ├── src/                    # C++/CUDA production source
   │   ├── Psd/                # Pade spectrum decomposition helpers
   │   ├── Main.cu             # Legacy executable workflow
   │   ├── Initialize.*        # System, bath, hierarchy, rho setup
   │   ├── Liouville.*         # Propagation and dRho evaluation
   │   ├── Matrixes.*          # Global device storage lifecycle
   │   └── TypeDef.h           # Scalar aliases and CUDA wrappers
   ├── tests/                  # Unit, CUDA, numerical, integration tests
   ├── examples/               # Checked-in reference output
   ├── scripts/                # Verification and release helpers
   └── doc/                    # Sphinx documentation

Development Principles
----------------------

* Preserve numerical semantics in cleanup-only changes.
* Use CTest labels and ``helix_add_test()`` for new tests.
* Keep generated run outputs out of Git.
* Document behavior from actual source, tests, and baseline fixtures.
* Prefer small Doxygen comments on declarations and longer rationale in
  narrative architecture pages.
