Generated C++/CUDA reference
============================

Doxygen reads public headers in ``include/helix`` and selected implementation
headers in the current ``src/`` tree. It still parses the ``*.cu`` translation
units so cross-references can resolve, but this Sphinx page avoids rendering the
raw Doxygen global index. That keeps anonymous implementation namespaces out of
the C++ API surface.

.. only:: no_doxygen

   Doxygen generation was skipped for this build. Unset
   ``HELIX_DOCS_SKIP_DOXYGEN`` and install Doxygen to render the generated
   C++/CUDA symbol index.

.. only:: not no_doxygen

   Public C++ API
   --------------

   .. doxygennamespace:: helix
      :project: HELIX
      :members:

   Parameters
   ----------

   .. doxygenfile:: parameters.h
      :project: HELIX

   Compile-time profile
   --------------------

   .. doxygenfile:: legacy_compile_options.h
      :project: HELIX

   Scalar and CUDA compatibility types
   -----------------------------------

   .. doxygenfile:: cuda_types.h
      :project: HELIX

   Initialization
   --------------

   .. doxygenfile:: initialize.h
      :project: HELIX

   .. doxygennamespace:: initialize_detail
      :project: HELIX
      :members:

   Liouville propagation
   ---------------------

   .. doxygenfile:: liouville.h
      :project: HELIX

   Matrix storage and utilities
   ----------------------------

   .. doxygenfile:: matrix_storage.h
      :project: HELIX

   .. doxygenfile:: matrix_util.h
      :project: HELIX

   Pade spectrum decomposition
   ---------------------------

   .. doxygenfile:: psd.h
      :project: HELIX

   .. doxygenfile:: eigenvalues.h
      :project: HELIX
