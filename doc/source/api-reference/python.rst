Experimental Python binding
===========================

HELIX v0.1 includes an optional experimental pybind11 binding over the public
C++ API. It is disabled by default, is built only in the CMake build tree, and
does not define a wheel, conda package, or long-term Python packaging contract.

Build and smoke
---------------

One verified local setup uses Python 3.13 and the ``dev`` extra:

.. code-block:: bash

   uv venv --python 3.13 .venv
   uv pip install -e ".[dev]"
   cmake -S . -B build/cmake-python-313 \
     -DCMAKE_BUILD_TYPE=Release \
     -DHELIX_BUILD_PYTHON=ON \
     -DPython3_EXECUTABLE="$PWD/.venv/bin/python"
   cmake --build build/cmake-python-313 --parallel "$(nproc)"
   ctest --test-dir build/cmake-python-313 -R v01_python_smoke_gate --output-on-failure

Use a fresh CMake build directory, or clear the CMake cache, when changing the
selected ``Python3_EXECUTABLE``.

Smoke snippet
-------------

.. code-block:: python

   import helix

   assert helix.runtime_version() == helix.__version__

   system = helix.examples.legacy_spin_glass_system()
   bath = helix.Bath.drude_lorentz_pade()
   hierarchy = helix.HierarchySpec.compiled_default(bath)
   options = helix.SolverOptions()
   options.steps = 2

   result = helix.HEOMSolver().run(system, hierarchy, options)
   assert result.ok(), result.diagnostics.summary()
   assert result.diagnostics.backend == helix.Backend.LegacyCudaSparse
   assert result.diagnostics.status == helix.RunStatus.Success

Supported surface
-----------------

The binding mirrors the public C++ API names for enums, ``Diagnostics``,
``ContextOptions``, ``SparseOperator``, ``Bath``, ``HierarchySpec``,
``SolverOptions``, ``System``, ``RunResult``, ``Context``, ``HEOMSolver``, and
``helix.examples.legacy_spin_glass_system``. It should not add Python-only
solver semantics ahead of the C++ library contract.
