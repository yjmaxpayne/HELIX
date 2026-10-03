#pragma once

#include <cstdio>

namespace helix::backend {

// The sparse funnel always uses a non-transposed A operand. Supporting other
// A operations belongs to a future backend-contract extension.
enum class SpmmOperation
{
	NonTranspose,
	Transpose
};

struct SpmmStatus
{
	bool ok = true;
	int nativeCode = 0;
};

// Sparse matrix multiplication contract:
// - Inputs: every pointer has device-pointer semantics, including alpha/beta.
// - Output: SpmmStatus reports success and a native code without throwing or
//   terminating the caller.
// - Errors: reportSpmmFailure prints the native code and lets execution continue.
// - Synchronization: work is enqueued asynchronously on the backend-bound
//   stream and obeys stream order, including interleaved transpose operations.
// - Ownership: every pointer is borrowed; neither the arguments nor the backend
//   take ownership or extend a pointee's lifetime.
// - Operation: transA is always non-transpose; only transB is configurable.
template <typename Scalar>
struct SpmmArgs
{
	SpmmOperation transB = SpmmOperation::NonTranspose;
	int m = 0;
	int n = 0;
	int k = 0;
	int nnz = 0;
	const Scalar* alpha = nullptr;
	const Scalar* csrValues = nullptr;
	const int* csrRowOffsets = nullptr;
	const int* csrColumns = nullptr;
	const Scalar* denseInput = nullptr;
	int ldb = 0;
	const Scalar* beta = nullptr;
	Scalar* denseOutput = nullptr;
	int ldc = 0;
};

template <typename Backend>
inline SpmmStatus spmm(Backend& backend, const SpmmArgs<typename Backend::Scalar>& args)
{
	return backend.spmm(args);
}

inline void reportSpmmFailure(const SpmmStatus& status)
{
	if(!status.ok)
	{
		std::printf("%d", status.nativeCode);
	}
}

} // namespace helix::backend
