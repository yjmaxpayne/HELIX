Generated C++/CUDA Reference
============================

This page is generated from public headers in ``include/helix`` and selected
implementation headers in the current ``src/`` tree. The ``*.cu`` translation
units are still parsed by Doxygen so cross-references can resolve, but this
Sphinx page avoids rendering the raw Doxygen global index. That keeps anonymous
implementation namespaces out of the C++ API surface.

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

   Compile-Time Profile
   --------------------

   .. doxygenfile:: legacy_compile_options.h
      :project: HELIX

   Scalar and CUDA Compatibility Types
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

   Liouville Propagation
   ---------------------

   .. doxygenfile:: liouville.h
      :project: HELIX

   Matrix Storage and Utilities
   ----------------------------

   .. doxygenfile:: matrix_storage.h
      :project: HELIX

   .. doxygenfile:: matrix_util.h
      :project: HELIX

   Pade Spectrum Decomposition
   ---------------------------

   .. doxygenfile:: psd.h
      :project: HELIX

   .. doxygenfile:: eigenvalues.h
      :project: HELIX
