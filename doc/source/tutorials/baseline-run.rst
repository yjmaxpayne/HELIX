=====================
Baseline Run Tutorial
=====================

This tutorial runs HELIX in the same shape used by the smoke verification
workflow.

1. Build the executable:

   .. code-block:: bash

      cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
      cmake --build build/cmake --parallel "$(nproc)"

2. Run from a scratch directory:

   .. code-block:: bash

      mkdir -p build/example-run
      cd build/example-run
      HELIX_STEPS=2 ../cmake/helix

3. Inspect generated files:

   .. code-block:: bash

      ls output*.txt snapshot_rho*.dat

4. Return to the repository root and use the verification wrapper:

   .. code-block:: bash

      HELIX_STEPS=2 scripts/verify_examples.sh

For numerical changes, replace ``HELIX_STEPS=2`` with ``HELIX_STEPS=1980`` and
compare against the full checked-in energy trace.
