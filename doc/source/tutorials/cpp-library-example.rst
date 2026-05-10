C++ library example
===================

This runs the public-header-only v0.1 C++ library smoke example.

1. Build HELIX:

   .. code-block:: bash

      cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
      cmake --build build/cmake --parallel "$(nproc)"

2. Run the example gate:

   .. code-block:: bash

      ctest --test-dir build/cmake -R v01_cpp_library_example_gate --output-on-failure

3. Inspect the source:

   .. code-block:: bash

      sed -n '1,120p' examples/cpp/legacy_spin_glass.cpp

The example includes only ``<helix/helix.h>``, constructs the legacy spin-glass
compatibility system, runs two steps through ``HEOMSolver``, and prints the
final reduced-density shape. It uses the core library contract, so it does not
write ``outputEnergy.txt``, ``output.txt``, ``output_rho*.txt``, or
``snapshot_rho*.dat``.
