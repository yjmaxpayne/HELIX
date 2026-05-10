C++/CUDA source API
===================

Doxygen and Breathe generate the C++/CUDA API pages from ``include/`` and
selected ``src/`` headers. The pages cover the v0.1 public C++ headers and the
implementation interfaces used by the executable and tests.

Architecture mapping
--------------------

.. code-block:: text

   include/helix/               public v0.1 C++ headers
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
* ``include/helix`` is the public C++ API starting point.
* Selected ``src`` pages are implementation references, not ABI promises.

Minimal library example
-----------------------

Consumer code should include public headers only:

.. code-block:: c++

   #include <helix/helix.h>

   #include <iostream>

   int main()
   {
       auto system = helix::examples::legacy_spin_glass_system();
       auto bath = helix::Bath::drude_lorentz_pade();
       auto hierarchy = helix::HierarchySpec::compiled_default(bath);

       helix::SolverOptions options;
       options.steps = 2;

       auto result = helix::HEOMSolver().run(system, hierarchy, options);
       if(!result.ok())
       {
           std::cerr << result.diagnostics.summary() << "\n";
           return 1;
       }

       return 0;
   }

The repository keeps the full smoke example in
``examples/cpp/legacy_spin_glass.cpp`` and compiles it through
``v01_cpp_library_example_gate``.

v0.1 support matrix
-------------------

.. list-table::
   :widths: 28 28 44
   :header-rows: 1

   * - Surface
     - Status
     - Notes
   * - ``HELIX::helix``
     - Supported foundation
     - Build-tree and install-tree consumer smoke tests are registered.
   * - ``<helix/helix.h>``
     - Supported foundation
     - Public headers avoid private legacy CUDA, Thrust, cuBLAS, and cuSPARSE
       types.
   * - ``helix::examples::legacy_spin_glass_system()``
     - Supported compatibility path
     - Adapter for the current compiled spin-glass model.
   * - ``System::from_sparse()``
     - Validation-only execution path
     - CSR schema validation exists; arbitrary sparse runtime execution reports
       ``UnsupportedExecution`` in v0.1.
   * - ``RunResult``
     - Final-state result path
     - Exposes ``times``, final reduced density, shape, and diagnostics.
   * - CLI output files
     - Executable-only
     - The library API does not write legacy output files.

Known limits
------------

* ``Backend::LegacyCudaSparse`` is the only runtime backend accepted in v0.1.
* ``Precision::Single`` is the only runtime precision accepted in v0.1.
* Concurrent contexts are rejected; use sequential create/run/destroy/recreate.
* ``ResultMode::FinalState`` is the only supported result mode.
* Non-default bath and hierarchy values report constrained or unsupported
  diagnostics.

Generated index
---------------

See :doc:`generated` for Doxygen/Breathe pages over the selected public
headers and helper namespaces.
