==============
Build and test
==============

Build commands
--------------

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"

Use ``-DHELIX_CUDA_ARCHITECTURES=<arch>`` when automatic GPU architecture
detection is not available.

CTest labels
------------

Register tests with ``helix_add_test()`` in ``CMakeLists.txt``. The accepted
labels are:

* ``unit``
* ``cuda``
* ``numerical``
* ``integration``
* ``baseline``
* ``sanitizer``
* ``benchmark``

GPU tests must pass the ``GPU`` option. The helper sets ``RESOURCE_LOCK gpu``
for every GPU test, adds the ``cuda`` label unless the test is a sanitizer-only
entry, and prevents ``unit`` from being mixed with GPU execution.

Useful selectors:

.. code-block:: bash

   ctest --test-dir build/cmake -L unit --output-on-failure
   ctest --test-dir build/cmake -L cuda -N
   ctest --test-dir build/cmake -L numerical --output-on-failure

Numerical changes
-----------------

Cleanup-only changes must preserve HEOM numerical semantics. For intentional
numerical changes, document the affected parameters, reference source, expected
baseline difference, and tolerance.

The default numerical profile is single precision with ``Param::N=1024``,
``Param::KMax=2``, ``Param::JMax=3``, and hierarchy size 10.
