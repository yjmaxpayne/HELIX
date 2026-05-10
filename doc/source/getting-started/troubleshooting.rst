===============
Troubleshooting
===============

CUDA architecture detection fails
---------------------------------

Pass the local architecture explicitly:

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release \
     -DHELIX_CUDA_ARCHITECTURES=89

Use the architecture that matches the target GPU.

Generated files appear in the source tree
-----------------------------------------

Run ``helix`` from a scratch directory. Generated files such as
``outputEnergy.txt`` and ``snapshot_rho<N>.dat`` are ignored by Git, except for
intentional reference data under ``examples/``.

Doxygen is missing during documentation build
---------------------------------------------

The C++/CUDA API reference requires Doxygen. HELIX uses the same pattern as
CUDA-Q: Doxygen extracts C++ API XML and Breathe renders it in Sphinx.

.. code-block:: bash

   sudo apt-get install doxygen

For non-API authoring checks only, set ``HELIX_DOCS_SKIP_DOXYGEN=1``. Full CI
and release documentation builds should keep Doxygen enabled.

CUDA tests need a GPU
---------------------

CTest entries that execute CUDA kernels are registered with ``GPU`` and reserve
the ``gpu`` resource lock. Use ``-N`` first when inspecting labels on a
non-GPU machine:

.. code-block:: bash

   ctest --test-dir build/cmake -L cuda -N
