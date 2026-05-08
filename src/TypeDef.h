#include "cublas_v2.h"
#include "cuComplex.h"
#include "DefineParameters.h"
#include "cusparse_v2.h"

#ifndef TYPEDINC
#define TYPEDINC
#ifdef DYNAMIC_DENSE
#define HEOM_CUBLAS_CALLABLE __host__ __device__
#else
#define HEOM_CUBLAS_CALLABLE __host__
#endif
#ifdef SINGLE
typedef cuComplex Complex;
typedef float real;
__host__ __device__ static __forceinline__ cuComplex make_Complex(double x,double y){return make_cuComplex((float)x,(float)y);}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasGemm(cublasHandle_t handle, cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k, const cuComplex *alpha, const cuComplex *A, int lda, const cuComplex *B, int ldb, const cuComplex *beta, cuComplex *C, int ldc)
{
	return cublasCgemm(handle,transa,transb,m,n,k,alpha,A,lda,B,ldb,beta,C,ldc);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasGeam(cublasHandle_t handle, cublasOperation_t transa, cublasOperation_t transb, int m, int n, const cuComplex *alpha, const cuComplex *A, int lda, const cuComplex *beta, const cuComplex *B, int ldb, cuComplex *C, int ldc)
{
	return cublasCgeam(handle,transa,transb,m,n,alpha,A,lda,beta,B,ldb,C,ldc);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasScal(cublasHandle_t handle, int n, const cuComplex *alpha, cuComplex *x, int incx)
{
	return cublasCscal(handle,n,alpha,x,incx);
}
__host__ __device__ static __forceinline__ Complex 
operator*(const Complex &a,const Complex &b) {
	return cuCmulf(a,b);
}
__host__ __device__ static __forceinline__ Complex 
operator+(const Complex &a,const Complex &b) {
	return cuCaddf(a,b);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasAxpy(cublasHandle_t handle, int n, const cuComplex *alpha, const cuComplex *x, int incx, cuComplex *y, int incy)
{
	return cublasCaxpy(handle,n,alpha,x,incx,y,incy);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasDgmm(cublasHandle_t handle, cublasSideMode_t mode, int m, int n, const cuComplex *A, int lda, const cuComplex *x, int incx, cuComplex *C, int ldc)
{
	return cublasCdgmm(handle,mode,m,n,A,lda,x,incx,C, ldc);
}
__host__ static inline cusparseStatus_t cusparseCsrmmSpMM(cusparseHandle_t handle, cusparseOperation_t transA, cusparseOperation_t transB, int m, int n, int k, int nnz, const cuComplex *alpha, const cusparseMatDescr_t descrA, const cuComplex *csrValA, const int *csrRowPtrA, const int *csrColIndA, const cuComplex *B, int ldb, const cuComplex *beta, cuComplex *C, int ldc)
{
	(void)descrA;
	cusparseSpMatDescr_t matA = nullptr;
	cusparseDnMatDescr_t matB = nullptr;
	cusparseDnMatDescr_t matC = nullptr;
	void* buffer = nullptr;
	size_t bufferSize = 0;

	cusparseStatus_t status = cusparseCreateCsr(&matA, m, k, nnz,
		const_cast<int*>(csrRowPtrA), const_cast<int*>(csrColIndA), const_cast<cuComplex*>(csrValA),
		CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I, CUSPARSE_INDEX_BASE_ZERO, CUDA_C_32F);
	if(status != CUSPARSE_STATUS_SUCCESS){ return status; }
	status = cusparseCreateDnMat(&matB, transB == CUSPARSE_OPERATION_NON_TRANSPOSE ? k : n,
		transB == CUSPARSE_OPERATION_NON_TRANSPOSE ? n : k, ldb, const_cast<cuComplex*>(B), CUDA_C_32F, CUSPARSE_ORDER_COL);
	if(status != CUSPARSE_STATUS_SUCCESS){ cusparseDestroySpMat(matA); return status; }
	status = cusparseCreateDnMat(&matC, m, n, ldc, C, CUDA_C_32F, CUSPARSE_ORDER_COL);
	if(status != CUSPARSE_STATUS_SUCCESS){ cusparseDestroyDnMat(matB); cusparseDestroySpMat(matA); return status; }
	status = cusparseSpMM_bufferSize(handle, transA, transB, alpha, matA, matB, beta, matC,
		CUDA_C_32F, CUSPARSE_SPMM_ALG_DEFAULT, &bufferSize);
	if(status == CUSPARSE_STATUS_SUCCESS && bufferSize > 0 && cudaMalloc(&buffer, bufferSize) != cudaSuccess){
		status = CUSPARSE_STATUS_ALLOC_FAILED;
	}
	if(status == CUSPARSE_STATUS_SUCCESS){
		status = cusparseSpMM(handle, transA, transB, alpha, matA, matB, beta, matC,
			CUDA_C_32F, CUSPARSE_SPMM_ALG_DEFAULT, buffer);
	}
	if(buffer != nullptr){ cudaFree(buffer); }
	cusparseDestroyDnMat(matC);
	cusparseDestroyDnMat(matB);
	cusparseDestroySpMat(matA);
	return status;
}
__host__ static inline cusparseStatus_t cusparseCsrmm(cusparseHandle_t handle, cusparseOperation_t transA, int m, int n, int k, int nnz, const cuComplex *alpha, const cusparseMatDescr_t descrA, const cuComplex *csrValA, const int *csrRowPtrA, const int *csrColIndA, const cuComplex *B, int ldb, const cuComplex *beta, cuComplex *C, int ldc)
{
	return cusparseCsrmmSpMM(handle, transA, CUSPARSE_OPERATION_NON_TRANSPOSE, m, n, k, nnz, alpha, descrA, csrValA, csrRowPtrA, csrColIndA, B, ldb, beta, C, ldc);
}
__host__ static inline cusparseStatus_t cusparseCsrmm2(cusparseHandle_t handle, cusparseOperation_t transA, cusparseOperation_t transB, int m, int n, int k, int nnz, const cuComplex *alpha, const cusparseMatDescr_t descrA, const cuComplex *csrValA, const int *csrRowPtrA, const int *csrColIndA, const cuComplex *B, int ldb, const cuComplex *beta, cuComplex *C, int ldc)
{
	return cusparseCsrmmSpMM(handle, transA, transB, m, n, k, nnz, alpha, descrA, csrValA, csrRowPtrA, csrColIndA, B, ldb, beta, C, ldc);
}

#else
typedef cuDoubleComplex Complex;
typedef double real;
__host__ __device__ static __forceinline__ cuDoubleComplex make_Complex(double x,double y){return make_cuDoubleComplex(x,y);}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasGemm(cublasHandle_t handle, cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k, const cuDoubleComplex *alpha, const cuDoubleComplex *A, int lda, const cuDoubleComplex *B, int ldb, const cuDoubleComplex *beta, cuDoubleComplex *C, int ldc)
{
	return cublasZgemm(handle,transa,transb,m,n,k,alpha,A,lda,B,ldb,beta,C,ldc);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasGeam(cublasHandle_t handle, cublasOperation_t transa, cublasOperation_t transb, int m, int n, const cuDoubleComplex *alpha, const cuDoubleComplex *A, int lda, const cuDoubleComplex *beta, const cuDoubleComplex *B, int ldb, cuDoubleComplex *C, int ldc)
{
	return cublasZgeam(handle,transa,transb,m,n,alpha,A,lda,beta,B,ldb,C,ldc);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasScal(cublasHandle_t handle, int n, const cuDoubleComplex *alpha, cuDoubleComplex *x, int incx)
{
	return cublasZscal(handle,n,alpha,x,incx);
}
__host__ __device__ static __forceinline__ Complex 
operator*(const Complex &a,const Complex &b) {
	return cuCmul(a,b);
}
__host__ __device__ static __forceinline__ Complex 
operator+(const Complex &a,const Complex &b) {
	return cuCadd(a,b);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasAxpy(cublasHandle_t handle, int n, const cuDoubleComplex *alpha, const cuDoubleComplex *x, int incx, cuDoubleComplex *y, int incy)
{
	return cublasZaxpy(handle,n,alpha,x,incx,y,incy);
}
HEOM_CUBLAS_CALLABLE static __forceinline__ cublasStatus_t cublasDgmm(cublasHandle_t handle, cublasSideMode_t mode, int m, int n, const cuDoubleComplex *A, int lda, const cuDoubleComplex *x, int incx, cuDoubleComplex *C, int ldc)
{
	return cublasZdgmm(handle,mode,m,n,A,lda,x,incx,C, ldc);
}
__host__ static inline cusparseStatus_t cusparseCsrmmSpMM(cusparseHandle_t handle, cusparseOperation_t transA, cusparseOperation_t transB, int m, int n, int k, int nnz, const cuDoubleComplex *alpha, const cusparseMatDescr_t descrA, const cuDoubleComplex *csrValA, const int *csrRowPtrA, const int *csrColIndA, const cuDoubleComplex *B, int ldb, const cuDoubleComplex *beta, cuDoubleComplex *C, int ldc)
{
	(void)descrA;
	cusparseSpMatDescr_t matA = nullptr;
	cusparseDnMatDescr_t matB = nullptr;
	cusparseDnMatDescr_t matC = nullptr;
	void* buffer = nullptr;
	size_t bufferSize = 0;

	cusparseStatus_t status = cusparseCreateCsr(&matA, m, k, nnz,
		const_cast<int*>(csrRowPtrA), const_cast<int*>(csrColIndA), const_cast<cuDoubleComplex*>(csrValA),
		CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I, CUSPARSE_INDEX_BASE_ZERO, CUDA_C_64F);
	if(status != CUSPARSE_STATUS_SUCCESS){ return status; }
	status = cusparseCreateDnMat(&matB, transB == CUSPARSE_OPERATION_NON_TRANSPOSE ? k : n,
		transB == CUSPARSE_OPERATION_NON_TRANSPOSE ? n : k, ldb, const_cast<cuDoubleComplex*>(B), CUDA_C_64F, CUSPARSE_ORDER_COL);
	if(status != CUSPARSE_STATUS_SUCCESS){ cusparseDestroySpMat(matA); return status; }
	status = cusparseCreateDnMat(&matC, m, n, ldc, C, CUDA_C_64F, CUSPARSE_ORDER_COL);
	if(status != CUSPARSE_STATUS_SUCCESS){ cusparseDestroyDnMat(matB); cusparseDestroySpMat(matA); return status; }
	status = cusparseSpMM_bufferSize(handle, transA, transB, alpha, matA, matB, beta, matC,
		CUDA_C_64F, CUSPARSE_SPMM_ALG_DEFAULT, &bufferSize);
	if(status == CUSPARSE_STATUS_SUCCESS && bufferSize > 0 && cudaMalloc(&buffer, bufferSize) != cudaSuccess){
		status = CUSPARSE_STATUS_ALLOC_FAILED;
	}
	if(status == CUSPARSE_STATUS_SUCCESS){
		status = cusparseSpMM(handle, transA, transB, alpha, matA, matB, beta, matC,
			CUDA_C_64F, CUSPARSE_SPMM_ALG_DEFAULT, buffer);
	}
	if(buffer != nullptr){ cudaFree(buffer); }
	cusparseDestroyDnMat(matC);
	cusparseDestroyDnMat(matB);
	cusparseDestroySpMat(matA);
	return status;
}
__host__ static inline cusparseStatus_t cusparseCsrmm(cusparseHandle_t handle, cusparseOperation_t transA, int m, int n, int k, int nnz, const cuDoubleComplex *alpha, const cusparseMatDescr_t descrA, const cuDoubleComplex *csrValA, const int *csrRowPtrA, const int *csrColIndA, const cuDoubleComplex *B, int ldb, const cuDoubleComplex *beta, cuDoubleComplex *C, int ldc)
{
	return cusparseCsrmmSpMM(handle, transA, CUSPARSE_OPERATION_NON_TRANSPOSE, m, n, k, nnz, alpha, descrA, csrValA, csrRowPtrA, csrColIndA, B, ldb, beta, C, ldc);
}
__host__ static inline cusparseStatus_t cusparseCsrmm2(cusparseHandle_t handle, cusparseOperation_t transA, cusparseOperation_t transB, int m, int n, int k, int nnz, const cuDoubleComplex *alpha, const cusparseMatDescr_t descrA, const cuDoubleComplex *csrValA, const int *csrRowPtrA, const int *csrColIndA, const cuDoubleComplex *B, int ldb, const cuDoubleComplex *beta, cuDoubleComplex *C, int ldc)
{
	return cusparseCsrmmSpMM(handle, transA, transB, m, n, k, nnz, alpha, descrA, csrValA, csrRowPtrA, csrColIndA, B, ldb, beta, C, ldc);
}
#endif

#endif
