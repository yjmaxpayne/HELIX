#pragma once

#include "backend/spmm_backend.h"
#include "cuda_sparse_backend_plan.h"
#include "cuda_types.h"
#include "library/backend_profiling.h"

#include <cstdlib>
#include <string>

namespace helix::backend {

// This CUDA-only adapter is included by liouville.cu alone. Keep it confined to
// that translation unit so the cached environment decision has one instance.
class CudaSparseBackend {
public:
	using Scalar = Complex;

	CudaSparseBackend(
		cusparseHandle_t handle,
		cudaStream_t stream,
		helix::cuda_backend::CudaSparseBackendPlan& nonTransposePlan,
		helix::cuda_backend::CudaSparseBackendPlan& transposePlan) noexcept
		: handle_(handle),
		  stream_(stream),
		  nonTransposePlan_(&nonTransposePlan),
		  transposePlan_(&transposePlan)
	{
	}

	cudaStream_t stream() const noexcept
	{
		return stream_;
	}

	SpmmStatus spmm(const SpmmArgs<Scalar>& args)
	{
		const cusparseOperation_t transB = toCusparseOperation(args.transB);
		cusparseStatus_t status = CUSPARSE_STATUS_SUCCESS;
		if(!reusePlanEnabled())
		{
			status = cusparseCsrmmSpMM(
				handle_,
				CUSPARSE_OPERATION_NON_TRANSPOSE,
				transB,
				args.m,
				args.n,
				args.k,
				args.nnz,
				args.alpha,
				nullptr,
				args.csrValues,
				args.csrRowOffsets,
				args.csrColumns,
				args.denseInput,
				args.ldb,
				args.beta,
				args.denseOutput,
				args.ldc);
			if(status == CUSPARSE_STATUS_SUCCESS)
			{
				helix::library::BackendSpmmProfilingCounters counters;
				counters.callCount = 1;
				counters.descriptorCreateCount = 3;
				counters.bufferSizeQueryCount = 1;
				helix::library::recordSpmmProfiling(counters);
			}
		}
		else
		{
			helix::cuda_backend::CudaSparseSpmmArgs nativeArgs;
			nativeArgs.handle = handle_;
			nativeArgs.stream = stream_;
			nativeArgs.transA = CUSPARSE_OPERATION_NON_TRANSPOSE;
			nativeArgs.transB = transB;
			nativeArgs.m = args.m;
			nativeArgs.n = args.n;
			nativeArgs.k = args.k;
			nativeArgs.nnz = args.nnz;
			nativeArgs.alpha = args.alpha;
			nativeArgs.csrValues = args.csrValues;
			nativeArgs.csrRowOffsets = args.csrRowOffsets;
			nativeArgs.csrColumns = args.csrColumns;
			nativeArgs.denseInput = args.denseInput;
			nativeArgs.ldb = args.ldb;
			nativeArgs.beta = args.beta;
			nativeArgs.denseOutput = args.denseOutput;
			nativeArgs.ldc = args.ldc;

			helix::cuda_backend::CudaSparseBackendPlan& plan =
				args.transB == SpmmOperation::NonTranspose
				? *nonTransposePlan_
				: *transposePlan_;
			status = plan.run(nativeArgs);
		}

		return {
			status == CUSPARSE_STATUS_SUCCESS,
			static_cast<int>(status)
		};
	}

private:
	static cusparseOperation_t toCusparseOperation(SpmmOperation operation) noexcept
	{
		switch(operation)
		{
		case SpmmOperation::NonTranspose:
			return CUSPARSE_OPERATION_NON_TRANSPOSE;
		case SpmmOperation::Transpose:
			return CUSPARSE_OPERATION_TRANSPOSE;
		}
		return CUSPARSE_OPERATION_NON_TRANSPOSE;
	}

	static bool reusePlanEnabled()
	{
		static const bool enabled = [] {
			const char* value = std::getenv("HELIX_CUSPARSE_REUSE_PLAN");
			if(value == nullptr || value[0] == '\0')
			{
				return false;
			}
			const std::string setting(value);
			return (setting == "1"
				|| setting == "true"
				|| setting == "True"
				|| setting == "TRUE"
				|| setting == "on"
				|| setting == "ON"
				|| setting == "yes"
				|| setting == "YES");
		}();
		return enabled;
	}

	cusparseHandle_t handle_ = nullptr;
	cudaStream_t stream_ = nullptr;
	helix::cuda_backend::CudaSparseBackendPlan* nonTransposePlan_ = nullptr;
	helix::cuda_backend::CudaSparseBackendPlan* transposePlan_ = nullptr;
};

} // namespace helix::backend
