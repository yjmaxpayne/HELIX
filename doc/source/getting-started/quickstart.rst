==========
Quickstart
==========

Run the short HELIX smoke baseline and check the generated files.

Build
-----

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"

Run a short example
-------------------

The executable writes output files in the current directory. Use a scratch
directory:

.. code-block:: bash

   mkdir -p build/example-run
   cd build/example-run
   HELIX_STEPS=2 ../cmake/helix

Use the repository verification wrapper from the repository root:

.. code-block:: bash

   HELIX_STEPS=2 scripts/verify_examples.sh

Run the C++ library example
---------------------------

The public C++ example uses only ``<helix/helix.h>`` and calls the current
legacy spin-glass compatibility adapter through the library API:

.. code-block:: bash

   ctest --test-dir build/cmake -R v01_cpp_library_example_gate --output-on-failure

The source is ``examples/cpp/legacy_spin_glass.cpp``. It returns a structured
``RunResult`` and does not write ``outputEnergy.txt``, ``output.txt``,
``output_rho*.txt``, or ``snapshot_rho*.dat``.

Run the full baseline
---------------------

Before merging numerical changes, run the full reference comparison:

.. code-block:: bash

   HELIX_STEPS=1000 scripts/verify_examples.sh

The checked-in ``examples/outputEnergy.txt`` contains 1981 rows, corresponding
to 1980 propagation steps plus the final output row. The full baseline command
compares the 1001-row prefix by default to keep verification time bounded.

Generated files
---------------

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - File
     - Meaning
   * - ``outputEnergy.txt``
     - Time and energy trace. This is the primary numerical baseline output.
   * - ``output.txt``
     - CUDA event timing per step. This is not a physics baseline.
   * - ``output_rho<N>.txt``
     - Text chunks for diagonal density values.
   * - ``snapshot_rho<N>.dat``
     - Binary snapshots of the hierarchy density state.

Runtime controls
----------------

``HELIX_STEPS`` controls the number of propagation steps. ``HEOM_STEPS`` is
accepted as a compatibility alias. Missing or invalid values fall back to the
legacy default of 1,000,000 steps.
