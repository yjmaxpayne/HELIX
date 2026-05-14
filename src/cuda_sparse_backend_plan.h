#pragma once

#include "cuda_runtime.h"
#include "cuda_types.h"
#include "cusparse_v2.h"

#include <cstddef>

namespace helix::cuda_backend {

struct CudaSparseSpmmArgs
{
	cusparseHandle_t handle = nullptr;
	cudaStream_t stream = nullptr;
	cusparseOperation_t transA = CUSPARSE_OPERATION_NON_TRANSPOSE;
	cusparseOperation_t transB = CUSPARSE_OPERATION_NON_TRANSPOSE;
	int m = 0;
	int n = 0;
	int k = 0;
	int nnz = 0;
	const Complex* alpha = nullptr;
	const Complex* csrValues = nullptr;
	const int* csrRowOffsets = nullptr;
	const int* csrColumns = nullptr;
	const Complex* denseInput = nullptr;
	int ldb = 0;
	const Complex* beta = nullptr;
	Complex* denseOutput = nullptr;
	int ldc = 0;
};

class CudaSparseBackendPlan {
public:
	CudaSparseBackendPlan() = default;
	~CudaSparseBackendPlan();

	CudaSparseBackendPlan(const CudaSparseBackendPlan&) = delete;
	CudaSparseBackendPlan& operator=(const CudaSparseBackendPlan&) = delete;

	CudaSparseBackendPlan(CudaSparseBackendPlan&& other) noexcept;
	CudaSparseBackendPlan& operator=(CudaSparseBackendPlan&& other) noexcept;

	cusparseStatus_t run(const CudaSparseSpmmArgs& args);
	void destroy() noexcept;

	bool initialized() const noexcept;
	std::size_t spmmCallCount() const noexcept;
	std::size_t descriptorCreateCount() const noexcept;
	std::size_t workspaceAllocCount() const noexcept;
	std::size_t workspaceBytes() const noexcept;
	std::size_t workspaceHighWaterBytes() const noexcept;
	std::size_t bufferSizeQueryCount() const noexcept;

private:
	struct Shape
	{
		cusparseOperation_t transA = CUSPARSE_OPERATION_NON_TRANSPOSE;
		cusparseOperation_t transB = CUSPARSE_OPERATION_NON_TRANSPOSE;
		int m = 0;
		int n = 0;
		int k = 0;
		int nnz = 0;
		int ldb = 0;
		int ldc = 0;
	};

	static Shape shapeFrom(const CudaSparseSpmmArgs& args) noexcept;
	static bool validArgs(const CudaSparseSpmmArgs& args) noexcept;

	cusparseStatus_t create(const CudaSparseSpmmArgs& args);
	cusparseStatus_t updateDensePointers(const CudaSparseSpmmArgs& args) noexcept;
	bool compatible(const CudaSparseSpmmArgs& args) const noexcept;
	void releaseDescriptors() noexcept;
	void moveFrom(CudaSparseBackendPlan& other) noexcept;

	cusparseSpMatDescr_t sparse_ = nullptr;
	cusparseDnMatDescr_t denseInput_ = nullptr;
	cusparseDnMatDescr_t denseOutput_ = nullptr;
	void* workspace_ = nullptr;
	std::size_t workspaceBytes_ = 0;
	std::size_t workspaceHighWaterBytes_ = 0;
	cusparseHandle_t handle_ = nullptr;
	cudaStream_t stream_ = nullptr;
	Shape shape_{};
	const Complex* csrValues_ = nullptr;
	const int* csrRowOffsets_ = nullptr;
	const int* csrColumns_ = nullptr;
	std::size_t spmmCallCount_ = 0;
	std::size_t descriptorCreateCount_ = 0;
	std::size_t workspaceAllocCount_ = 0;
	std::size_t bufferSizeQueryCount_ = 0;
};

} // namespace helix::cuda_backend
