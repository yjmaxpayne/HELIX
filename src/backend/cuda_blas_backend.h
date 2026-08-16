#pragma once

#include "backend/blas_backend.h"
#include "cuda_types.h"

namespace helix::backend {

// CUDA-only adapter over an externally owned cuBLAS handle. The handle keeps
// its caller-configured stream binding and pointer mode; the adapter neither
// rebinds nor converts them (see the alpha semantics note in blas_backend.h).
class CudaBlasBackend {
public:
	using Scalar = Complex;

	explicit CudaBlasBackend(cublasHandle_t handle) noexcept
		: handle_(handle)
	{
	}

	BlasStatus axpy(const AxpyArgs<Scalar>& args)
	{
		const cublasStatus_t status = cublasAxpy(
			handle_,
			args.n,
			args.alpha,
			args.x,
			args.incx,
			args.y,
			args.incy);
		return {status == CUBLAS_STATUS_SUCCESS, static_cast<int>(status)};
	}

	BlasStatus scal(const ScalArgs<Scalar>& args)
	{
		const cublasStatus_t status = cublasScal(
			handle_,
			args.n,
			args.alpha,
			args.x,
			args.incx);
		return {status == CUBLAS_STATUS_SUCCESS, static_cast<int>(status)};
	}

private:
	cublasHandle_t handle_ = nullptr;
};

} // namespace helix::backend
