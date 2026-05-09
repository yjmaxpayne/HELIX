Generated C++/CUDA Reference
============================

This page is generated from public header files in the current ``src/`` tree.
The ``*.cu`` translation units are still parsed by Doxygen so cross-references
can resolve, but this Sphinx page avoids rendering the raw Doxygen global index.
That keeps anonymous implementation namespaces out of the C++ API surface.

.. only:: no_doxygen

   Doxygen generation was skipped for this build. Unset
   ``HELIX_DOCS_SKIP_DOXYGEN`` and install Doxygen to render the generated
   C++/CUDA symbol index.

.. only:: not no_doxygen

   Parameters
   ----------

   .. doxygenfile:: Parameters.h
      :project: HELIX

   Compile-Time Profile
   --------------------

   .. doxygenfile:: DefineParameters.h
      :project: HELIX

   Scalar and CUDA Compatibility Types
   -----------------------------------

   .. doxygenfile:: TypeDef.h
      :project: HELIX

   Initialization
   --------------

   .. doxygenfile:: Initialize.h
      :project: HELIX

   .. doxygennamespace:: initialize_detail
      :project: HELIX
      :members:

   Liouville Propagation
   ---------------------

   .. doxygenfile:: Liouville.h
      :project: HELIX

   Matrix Storage and Utilities
   ----------------------------

   .. doxygenfile:: Matrixes.h
      :project: HELIX

   .. doxygenfile:: MatrixUtil.h
      :project: HELIX

   Pade Spectrum Decomposition
   ---------------------------

   .. doxygenfile:: Psd.h
      :project: HELIX

   .. doxygenfile:: Eigval.h
      :project: HELIX
