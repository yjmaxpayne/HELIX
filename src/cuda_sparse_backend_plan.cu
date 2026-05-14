#include "cuda_sparse_backend_plan.h"

#include "library/backend_profiling.h"

#include <algorithm>
#include <utility>

namespace helix::cuda_backend {

namespace {

cudaDataType complexCudaDataType() noexcept
{
#ifdef SINGLE
	return CUDA_C_32F;
#else
	return CUDA_C_64F;
#endif
}

cusparseStatus_t cusparseStatusFromCuda(cudaError_t status) noexcept
{
	if(status == cudaSuccess)
	{
		return CUSPARSE_STATUS_SUCCESS;
	}
	if(status == cudaErrorMemoryAllocation)
	{
		return CUSPARSE_STATUS_ALLOC_FAILED;
	}
	return CUSPARSE_STATUS_INTERNAL_ERROR;
}

void recordSpmmDelta(std::size_t callCount,
	std::size_t descriptorCreateCount,
	std::size_t workspaceAllocCount,
	std::size_t workspaceBytes,
	std::size_t bufferSizeQueryCount) noexcept
{
	helix::library::BackendSpmmProfilingCounters counters;
	counters.callCount = callCount;
	counters.descriptorCreateCount = descriptorCreateCount;
	counters.workspaceAllocCount = workspaceAllocCount;
	counters.workspaceBytes = workspaceBytes;
	counters.bufferSizeQueryCount = bufferSizeQueryCount;
	helix::library::recordSpmmProfiling(counters);
}

} // namespace

CudaSparseBackendPlan::~CudaSparseBackendPlan()
{
	destroy();
}

CudaSparseBackendPlan::CudaSparseBackendPlan(CudaSparseBackendPlan&& other) noexcept
{
	moveFrom(other);
}

CudaSparseBackendPlan& CudaSparseBackendPlan::operator=(CudaSparseBackendPlan&& other) noexcept
{
	if(this != &other)
	{
		destroy();
		moveFrom(other);
	}
	return *this;
}

CudaSparseBackendPlan::Shape CudaSparseBackendPlan::shapeFrom(const CudaSparseSpmmArgs& args) noexcept
{
	Shape shape;
	shape.transA = args.transA;
	shape.transB = args.transB;
	shape.m = args.m;
	shape.n = args.n;
	shape.k = args.k;
	shape.nnz = args.nnz;
	shape.ldb = args.ldb;
	shape.ldc = args.ldc;
	return shape;
}

bool CudaSparseBackendPlan::validArgs(const CudaSparseSpmmArgs& args) noexcept
{
	return args.handle != nullptr
		&& args.m > 0
		&& args.n > 0
		&& args.k > 0
		&& args.nnz >= 0
		&& args.alpha != nullptr
		&& args.beta != nullptr
		&& args.csrValues != nullptr
		&& args.csrRowOffsets != nullptr
		&& args.csrColumns != nullptr
		&& args.denseInput != nullptr
		&& args.denseOutput != nullptr
		&& args.ldb > 0
		&& args.ldc > 0;
}

cusparseStatus_t CudaSparseBackendPlan::create(const CudaSparseSpmmArgs& args)
{
	if(!validArgs(args))
	{
		return CUSPARSE_STATUS_INVALID_VALUE;
	}

	handle_ = args.handle;
	stream_ = args.stream;
	shape_ = shapeFrom(args);
	csrValues_ = args.csrValues;
	csrRowOffsets_ = args.csrRowOffsets;
	csrColumns_ = args.csrColumns;

	if(stream_ != nullptr)
	{
		const cusparseStatus_t streamStatus = cusparseSetStream(handle_, stream_);
		if(streamStatus != CUSPARSE_STATUS_SUCCESS)
		{
			return streamStatus;
		}
	}

	cusparseStatus_t status = cusparseCreateCsr(&sparse_,
		args.m,
		args.k,
		args.nnz,
		const_cast<int*>(args.csrRowOffsets),
		const_cast<int*>(args.csrColumns),
		const_cast<Complex*>(args.csrValues),
		CUSPARSE_INDEX_32I,
		CUSPARSE_INDEX_32I,
		CUSPARSE_INDEX_BASE_ZERO,
		complexCudaDataType());
	if(status != CUSPARSE_STATUS_SUCCESS)
	{
		releaseDescriptors();
		return status;
	}
	descriptorCreateCount_++;

	const int denseInputRows = args.transB == CUSPARSE_OPERATION_NON_TRANSPOSE ? args.k : args.n;
	const int denseInputCols = args.transB == CUSPARSE_OPERATION_NON_TRANSPOSE ? args.n : args.k;
	status = cusparseCreateDnMat(&denseInput_,
		denseInputRows,
		denseInputCols,
		args.ldb,
		const_cast<Complex*>(args.denseInput),
		complexCudaDataType(),
		CUSPARSE_ORDER_COL);
	if(status != CUSPARSE_STATUS_SUCCESS)
	{
		releaseDescriptors();
		return status;
	}
	descriptorCreateCount_++;

	status = cusparseCreateDnMat(&denseOutput_,
		args.m,
		args.n,
		args.ldc,
		args.denseOutput,
		complexCudaDataType(),
		CUSPARSE_ORDER_COL);
	if(status != CUSPARSE_STATUS_SUCCESS)
	{
		releaseDescriptors();
		return status;
	}
	descriptorCreateCount_++;

	bufferSizeQueryCount_++;
	status = cusparseSpMM_bufferSize(handle_,
		args.transA,
		args.transB,
		args.alpha,
		sparse_,
		denseInput_,
		args.beta,
		denseOutput_,
		complexCudaDataType(),
		CUSPARSE_SPMM_ALG_DEFAULT,
		&workspaceBytes_);
	if(status != CUSPARSE_STATUS_SUCCESS)
	{
		releaseDescriptors();
		return status;
	}

	workspaceHighWaterBytes_ = std::max(workspaceHighWaterBytes_, workspaceBytes_);
	if(workspaceBytes_ > 0)
	{
		const cudaError_t allocationStatus = cudaMalloc(&workspace_, workspaceBytes_);
		status = cusparseStatusFromCuda(allocationStatus);
		if(status != CUSPARSE_STATUS_SUCCESS)
		{
			workspace_ = nullptr;
			releaseDescriptors();
			return status;
		}
		workspaceAllocCount_++;
	}

	return CUSPARSE_STATUS_SUCCESS;
}

cusparseStatus_t CudaSparseBackendPlan::updateDensePointers(const CudaSparseSpmmArgs& args) noexcept
{
	cusparseStatus_t status = cusparseDnMatSetValues(denseInput_, const_cast<Complex*>(args.denseInput));
	if(status != CUSPARSE_STATUS_SUCCESS)
	{
		return status;
	}
	return cusparseDnMatSetValues(denseOutput_, args.denseOutput);
}

bool CudaSparseBackendPlan::compatible(const CudaSparseSpmmArgs& args) const noexcept
{
	const Shape shape = shapeFrom(args);
	return handle_ == args.handle
		&& stream_ == args.stream
		&& shape_.transA == shape.transA
		&& shape_.transB == shape.transB
		&& shape_.m == shape.m
		&& shape_.n == shape.n
		&& shape_.k == shape.k
		&& shape_.nnz == shape.nnz
		&& shape_.ldb == shape.ldb
		&& shape_.ldc == shape.ldc
		&& csrValues_ == args.csrValues
		&& csrRowOffsets_ == args.csrRowOffsets
		&& csrColumns_ == args.csrColumns;
}

cusparseStatus_t CudaSparseBackendPlan::run(const CudaSparseSpmmArgs& args)
{
	const std::size_t previousDescriptorCreateCount = descriptorCreateCount_;
	const std::size_t previousWorkspaceAllocCount = workspaceAllocCount_;
	const std::size_t previousBufferSizeQueryCount = bufferSizeQueryCount_;

	if(!initialized())
	{
		const cusparseStatus_t status = create(args);
		if(status != CUSPARSE_STATUS_SUCCESS)
		{
			return status;
		}
	}
	else if(!compatible(args))
	{
		return CUSPARSE_STATUS_INVALID_VALUE;
	}

	cusparseStatus_t status = updateDensePointers(args);
	if(status != CUSPARSE_STATUS_SUCCESS)
	{
		return status;
	}

	status = cusparseSpMM(handle_,
		args.transA,
		args.transB,
		args.alpha,
		sparse_,
		denseInput_,
		args.beta,
		denseOutput_,
		complexCudaDataType(),
		CUSPARSE_SPMM_ALG_DEFAULT,
		workspace_);
	if(status == CUSPARSE_STATUS_SUCCESS)
	{
		spmmCallCount_++;
		recordSpmmDelta(1,
			descriptorCreateCount_ - previousDescriptorCreateCount,
			workspaceAllocCount_ - previousWorkspaceAllocCount,
			workspaceHighWaterBytes_,
			bufferSizeQueryCount_ - previousBufferSizeQueryCount);
	}
	return status;
}

void CudaSparseBackendPlan::destroy() noexcept
{
	if(workspace_ != nullptr)
	{
		cudaFree(workspace_);
		workspace_ = nullptr;
	}
	workspaceBytes_ = 0;
	releaseDescriptors();
	handle_ = nullptr;
	stream_ = nullptr;
	shape_ = Shape{};
	csrValues_ = nullptr;
	csrRowOffsets_ = nullptr;
	csrColumns_ = nullptr;
}

bool CudaSparseBackendPlan::initialized() const noexcept
{
	return sparse_ != nullptr && denseInput_ != nullptr && denseOutput_ != nullptr;
}

std::size_t CudaSparseBackendPlan::spmmCallCount() const noexcept
{
	return spmmCallCount_;
}

std::size_t CudaSparseBackendPlan::descriptorCreateCount() const noexcept
{
	return descriptorCreateCount_;
}

std::size_t CudaSparseBackendPlan::workspaceAllocCount() const noexcept
{
	return workspaceAllocCount_;
}

std::size_t CudaSparseBackendPlan::workspaceBytes() const noexcept
{
	return workspaceBytes_;
}

std::size_t CudaSparseBackendPlan::workspaceHighWaterBytes() const noexcept
{
	return workspaceHighWaterBytes_;
}

std::size_t CudaSparseBackendPlan::bufferSizeQueryCount() const noexcept
{
	return bufferSizeQueryCount_;
}

void CudaSparseBackendPlan::releaseDescriptors() noexcept
{
	if(denseOutput_ != nullptr)
	{
		cusparseDestroyDnMat(denseOutput_);
		denseOutput_ = nullptr;
	}
	if(denseInput_ != nullptr)
	{
		cusparseDestroyDnMat(denseInput_);
		denseInput_ = nullptr;
	}
	if(sparse_ != nullptr)
	{
		cusparseDestroySpMat(sparse_);
		sparse_ = nullptr;
	}
}

void CudaSparseBackendPlan::moveFrom(CudaSparseBackendPlan& other) noexcept
{
	sparse_ = std::exchange(other.sparse_, nullptr);
	denseInput_ = std::exchange(other.denseInput_, nullptr);
	denseOutput_ = std::exchange(other.denseOutput_, nullptr);
	workspace_ = std::exchange(other.workspace_, nullptr);
	workspaceBytes_ = std::exchange(other.workspaceBytes_, 0);
	workspaceHighWaterBytes_ = std::exchange(other.workspaceHighWaterBytes_, 0);
	handle_ = std::exchange(other.handle_, nullptr);
	stream_ = std::exchange(other.stream_, nullptr);
	shape_ = other.shape_;
	other.shape_ = Shape{};
	csrValues_ = std::exchange(other.csrValues_, nullptr);
	csrRowOffsets_ = std::exchange(other.csrRowOffsets_, nullptr);
	csrColumns_ = std::exchange(other.csrColumns_, nullptr);
	spmmCallCount_ = std::exchange(other.spmmCallCount_, 0);
	descriptorCreateCount_ = std::exchange(other.descriptorCreateCount_, 0);
	workspaceAllocCount_ = std::exchange(other.workspaceAllocCount_, 0);
	bufferSizeQueryCount_ = std::exchange(other.bufferSizeQueryCount_, 0);
}

} // namespace helix::cuda_backend
