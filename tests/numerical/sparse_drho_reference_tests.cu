#include "initialize.h"
#include "library/backend_profiling.h"
#include "liouville.h"
#include "matrix_storage.h"
#include "parameters.h"
#include "support/assert.h"
#include "support/numerical_invariants.h"

#include <cuda_runtime.h>
#include <iostream>
#include <thrust/host_vector.h>

namespace {

#ifdef SINGLE
constexpr const char* kPrecision = "single";
constexpr double kAbsTolerance = 1.0e-5;
constexpr double kRelTolerance = 1.0e-5;
#else
constexpr const char* kPrecision = "double";
constexpr double kAbsTolerance = 1.0e-10;
constexpr double kRelTolerance = 1.0e-10;
#endif

void cleanupRuntime()
{
	clearLiouvilleStorage();
	clearMatrixStorage();
	if(cublasHandle != nullptr)
	{
		cublasDestroy(cublasHandle);
		cublasHandle = nullptr;
	}
}

void printReferenceInput()
{
	std::cout << "reference_input: precision=" << kPrecision << " system_size=" << Param::N
			  << " hierarchy_size=" << hierarchySize << " step=" << Param::Step
			  << " integration_order=" << Param::IntegrationNum
			  << " toy_profile=disabled(default configuration MVP)" << '\n';
}

std::size_t expectedSpmmCallsPerHierarchyBlock()
{
	std::size_t calls = 6;
#ifdef USE_COUNTER
	calls += 2;
#endif
	return calls;
}

void testSparseDrhoInvariants(helix::test::Reporter& test)
{
	initialize();
	printReferenceInput();

	device_vector<Complex> derivative(dRho.size(), make_Complex(0.0, 0.0));
	helix::library::BackendProfilingCounters profilingSnapshot;
	{
		helix::library::ScopedBackendProfiling profiling;
		getdRhoSparse(dRho, derivative);
		test.expect(cudaDeviceSynchronize() == cudaSuccess, "sparse dRho computation completes");
		profilingSnapshot = profiling.snapshot();
	}
	const std::size_t expectedSpmmCalls =
		static_cast<std::size_t>(hierarchySize) * expectedSpmmCallsPerHierarchyBlock();
	std::cout << "sparse_dRho_h_diagonal_elementwise_spmm_calls: actual="
			  << profilingSnapshot.spmm.callCount.value_or(0)
			  << " expected=" << expectedSpmmCalls
			  << " reference=H_DIAGONAL elementwise path leaves only V-path SpMM calls" << '\n';
	test.expect(
		profilingSnapshot.spmm.callCount.value_or(0) == expectedSpmmCalls,
		"sparse dRho H diagonal specialization removes H-path SpMM calls");

	const thrust::host_vector<Complex> actual = derivative;
	test.expect(helix::test::allFinite(actual), "sparse dRho values remain finite");

	const helix::test::DiffStats traceDiff = helix::test::compareScalar(
		helix::test::traceBlock(actual, Param::N, 0),
		helix::test::ComplexScalar{0.0, 0.0});
	helix::test::printDiffStats(
		std::cout,
		"sparse_dRho_trace",
		traceDiff,
		kAbsTolerance,
		kRelTolerance,
		"trace conservation derivative for reduced density matrix");
	test.expect(
		traceDiff.maxAbs <= kAbsTolerance && traceDiff.maxRel <= kRelTolerance,
		"sparse dRho reduced trace derivative remains zero within tolerance");

	const helix::test::DiffStats hermiticityDiff = helix::test::hermiticityDiffBlock(actual, Param::N, 0);
	helix::test::printDiffStats(
		std::cout,
		"sparse_dRho_hermiticity",
		hermiticityDiff,
		kAbsTolerance,
		kRelTolerance,
		"Hermiticity preservation for reduced density derivative");
	test.expect(
		hermiticityDiff.maxAbs <= kAbsTolerance && hermiticityDiff.maxRel <= kRelTolerance,
		"sparse dRho reduced block remains Hermitian within tolerance");

	cleanupRuntime();
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testSparseDrhoInvariants(test);

	return test.finish("sparse dRho reference tests");
}
