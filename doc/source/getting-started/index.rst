===============
Getting Started
===============

This section covers the shortest path from a clean checkout to a verified HELIX
run. HELIX currently targets source builds on Linux with an NVIDIA GPU.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   installation
   quickstart
   troubleshooting

Key Requirements
----------------

* CMake 3.24 or newer
* C++17 and CUDA C++17 language modes
* CUDA Toolkit 13.0 or newer
* NVIDIA GPU with cuBLAS and cuSPARSE available
* Python 3.11 or newer for documentation tooling

Next Steps
----------

1. Start with :doc:`installation` to configure the build environment.
2. Continue with :doc:`quickstart` to run the smoke baseline.
3. Use :doc:`troubleshooting` if CUDA architecture detection or generated
   output handling fails.

See Also
--------

* :doc:`../development/index` for contributor commands
* :doc:`../api-reference/index` for source-level API documentation
* :doc:`../architecture/index` for runtime architecture
