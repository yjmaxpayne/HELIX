#pragma once

#include <cstdio>

namespace helix::backend {

struct TransposeStatus
{
	bool ok = true;
	int nativeCode = 0;
};

// Contract-level diagnostics use negative values. CUDA-native diagnostics
// are non-negative, so both domains remain unambiguous in nativeCode.
inline constexpr int kTransposeInvalidArguments = -1;
inline constexpr int kTransposeTileConstraintViolation = -2;

// Materialized in-place transpose contract:
// - In-place square n×n plain transpose (no conjugate); data has
//   device-pointer semantics.
// - Shape: n must be a positive multiple of 32 (current contract semantics,
//   materialized from the CUDA tile kernel; a future backend MAY relax this
//   by widening, never narrowing, accepted shapes).
// - Output: TransposeStatus reports success and a native or contract-level
//   diagnostic code without throwing or terminating the caller.
// - Errors: reportTransposeFailure prints the diagnostic and lets execution
//   continue (printf-and-continue, byte-compatible with sibling contracts).
// - Synchronization: work is enqueued asynchronously on the backend-bound
//   stream and obeys stream order -- the same stream as the backend's spmm(),
//   which preserves the required SpMM/transpose interleaving.
// - Ownership: data is borrowed; neither the arguments nor the backend take
//   ownership or extend the pointee's lifetime.
template <typename Scalar>
struct TransposeArgs
{
	Scalar* data = nullptr;
	int n = 0;
};

// Invalid arguments never reach the backend. The low-level entry point keeps
// the same guard as defense in depth for callers that bypass this contract.
template <typename Backend>
inline TransposeStatus transpose(Backend& backend, const TransposeArgs<typename Backend::Scalar>& args)
{
	if(args.data == nullptr || args.n <= 0)
	{
		return {false, kTransposeInvalidArguments};
	}
	if(args.n % 32 != 0)
	{
		return {false, kTransposeTileConstraintViolation};
	}
	return backend.transpose(args);
}

inline void reportTransposeFailure(const TransposeStatus& status)
{
	if(!status.ok)
	{
		std::printf("%d", status.nativeCode);
	}
}

} // namespace helix::backend
