=============
Runtime model
=============

The current runtime is a legacy executable workflow with explicit global CUDA
state. It works for regression testing, but it is not the final library API.

Execution sequence
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

Cleanup contract
----------------

Code that calls runtime functions in-process must release global resources:

.. code-block:: c++

   clearLiouvilleStorage();
   clearMatrixStorage();
   cublasDestroy(cublasHandle);
   cublasHandle = nullptr;

Next library boundary
---------------------

The library boundary should be an explicit HEOM context that owns parameters,
device vectors, CUDA handles, sparse caches, and output policy. Python bindings
should start from that boundary once it exists.
