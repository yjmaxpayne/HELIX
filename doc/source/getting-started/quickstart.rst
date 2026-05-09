==========
Quickstart
==========

This guide runs the short HELIX smoke baseline and explains the generated
files.

Build
-----

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"

Run a Short Example
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

Run the Full Baseline
---------------------

Before merging numerical changes, run the full reference comparison:

.. code-block:: bash

   HELIX_STEPS=1980 scripts/verify_examples.sh

The checked-in ``examples/outputEnergy.txt`` contains 1981 rows, corresponding
to 1980 propagation steps plus the final output row.

Generated Files
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

Runtime Controls
----------------

``HELIX_STEPS`` controls the number of propagation steps. ``HEOM_STEPS`` is
accepted as a compatibility alias. Missing or invalid values fall back to the
legacy default of 1,000,000 steps.
