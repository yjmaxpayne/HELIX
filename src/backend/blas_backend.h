#pragma once

#include <cstdio>

namespace helix::backend {

struct BlasStatus
{
	bool ok = true;
	int nativeCode = 0;
};

// Level-1 BLAS contract (axpy / scal):
// - Inputs: x/y have device-pointer semantics. alpha is borrowed with the
//   pointer semantics of the backend's bound handle: the sparse hierarchy
//   funnel binds device pointer mode, the develop()/CLI funnel binds the
//   default host pointer mode. The contract does not convert between them.
// - Output: BlasStatus reports success and a native code without throwing or
//   terminating the caller.
// - Errors: reportBlasFailure prints the native code and lets execution
//   continue.
// - Synchronization: work is enqueued asynchronously on the backend-bound
//   stream and obeys stream order.
// - Ownership: every pointer is borrowed; neither the arguments nor the
//   backend take ownership or extend a pointee's lifetime.
template <typename Scalar>
struct AxpyArgs
{
	int n = 0;
	const Scalar* alpha = nullptr;
	const Scalar* x = nullptr;
	int incx = 1;
	Scalar* y = nullptr;
	int incy = 1;
};

template <typename Scalar>
struct ScalArgs
{
	int n = 0;
	const Scalar* alpha = nullptr;
	Scalar* x = nullptr;
	int incx = 1;
};

template <typename Backend>
inline BlasStatus axpy(Backend& backend, const AxpyArgs<typename Backend::Scalar>& args)
{
	return backend.axpy(args);
}

template <typename Backend>
inline BlasStatus scal(Backend& backend, const ScalArgs<typename Backend::Scalar>& args)
{
	return backend.scal(args);
}

inline void reportBlasFailure(const BlasStatus& status)
{
	if(!status.ok)
	{
		std::printf("%d", status.nativeCode);
	}
}

} // namespace helix::backend
