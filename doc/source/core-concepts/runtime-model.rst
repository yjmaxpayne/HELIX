=============
Runtime Model
=============

The current runtime is a legacy executable workflow with explicit global CUDA
state. This model is stable enough for regression testing but not the final
library API.

Execution Sequence
------------------

.. code-block:: text

   initialize()
     initialize PSD data
     build temperature-dependent bath coefficients
     create dense and sparse system operators
     create cuBLAS handle
     build hierarchy rows and edges
     allocate rho and buffers
     initialize device constants

   loop over HELIX_STEPS
     output rho and energy at configured intervals
     develop()

   final output and cleanup

Cleanup Contract
----------------

Code that calls runtime functions in-process must release global resources:

.. code-block:: c++

   clearLiouvilleStorage();
   clearMatrixStorage();
   cublasDestroy(cublasHandle);
   cublasHandle = nullptr;

Future Direction
----------------

The planned library boundary is an explicit HEOM context that owns parameters,
device vectors, CUDA handles, sparse caches, and output policy. That boundary
will be the natural anchor for a future Python API.
