#include "initialize.h"
#include "library/backend_profiling.h"
#include "liouville.h"
#include "matrix_storage.h"
#include "parameters.h"
#include "support/assert.h"
#include "support/numerical_invariants.h"

#include <cuda_runtime.h>
#include <iostream>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/device_ptr.h>

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

void expectReducedDensityInvariants(
	helix::test::Reporter& test,
	const thrust::host_vector<Complex>& rho,
	const char* traceName,
	const char* hermiticityName)
{
	const helix::test::DiffStats traceDiff = helix::test::compareScalar(
		helix::test::traceBlock(rho, Param::N, 0),
		helix::test::ComplexScalar{1.0, 0.0});
	helix::test::printDiffStats(
		std::cout,
		traceName,
		traceDiff,
		kAbsTolerance,
		kRelTolerance,
		"unit trace of reduced density matrix");
	test.expect(
		traceDiff.maxAbs <= kAbsTolerance && traceDiff.maxRel <= kRelTolerance,
		"one-step reduced trace remains one within tolerance");

	const helix::test::DiffStats hermiticityDiff = helix::test::hermiticityDiffBlock(rho, Param::N, 0);
	helix::test::printDiffStats(
		std::cout,
		hermiticityName,
		hermiticityDiff,
		kAbsTolerance,
		kRelTolerance,
		"Hermiticity preservation for reduced density matrix");
	test.expect(
		hermiticityDiff.maxAbs <= kAbsTolerance && hermiticityDiff.maxRel <= kRelTolerance,
		"one-step reduced block remains Hermitian within tolerance");
}

thrust::device_vector<Complex> copyBasedIntegratorReference(
	helix::test::Reporter& test,
	const thrust::host_vector<Complex>& initial,
	int integrationOrder)
{
	const int rhoSize=hierarchySize*Param::N2;
	thrust::device_vector<Complex> current=initial;
	thrust::device_vector<Complex> derivative(rhoSize);
	thrust::device_vector<Complex> accumulator=current;
	const Complex one=make_Complex(1.0,0.0);
	for(int j=1;j<=integrationOrder;j++)
	{
#ifdef DYNAMIC_DENSE
		getdRhowithBLAS(current,derivative);
#else
		getdRhoSparse(current,derivative);
#endif
		const Complex tj=make_Complex(Param::Step/j,0.0);
		test.expect(
			cublasScal(cublasHandle,rhoSize,&tj,thrust::raw_pointer_cast(derivative.data()),1)
				== CUBLAS_STATUS_SUCCESS,
			"copy reference scales recurrence derivative");
		test.expect(
			cublasAxpy(cublasHandle,rhoSize,&one,thrust::raw_pointer_cast(derivative.data()),1,
				thrust::raw_pointer_cast(accumulator.data()),1) == CUBLAS_STATUS_SUCCESS,
			"copy reference accumulates recurrence derivative");
		test.expect(cudaDeviceSynchronize() == cudaSuccess, "copy reference recurrence order completes");
		current=derivative;
	}
	return accumulator;
}

void testIntegratorSwapMatchesCopyReferenceAndRecordsD2D(helix::test::Reporter& test)
{
	const int integrationOrder=4;
	Param::IntegrationNum=integrationOrder;
	initialize();
	printReferenceInput();

	const thrust::host_vector<Complex> initial=dRho;
	const thrust::device_vector<Complex> referenceDevice =
		copyBasedIntegratorReference(test,initial,integrationOrder);
	const thrust::host_vector<Complex> reference=referenceDevice;

	dRho=initial;
	helix::library::BackendProfilingCounters profilingSnapshot;
	{
		helix::library::ScopedBackendProfiling profiling;
		develop();
		test.expect(cudaDeviceSynchronize() == cudaSuccess, "swap recurrence develop completes");
		profilingSnapshot=profiling.snapshot();
	}
	const thrust::host_vector<Complex> actual=dRho;

	const helix::test::DiffStats recurrenceDiff=helix::test::vectorDiff(actual,reference);
	helix::test::printDiffStats(
		std::cout,
		"integrator_swap_vs_copy_reference",
		recurrenceDiff,
		kAbsTolerance,
		kRelTolerance,
		"copy-based Taylor recurrence reference for each intermediate order");
	test.expect(
		recurrenceDiff.maxAbs <= kAbsTolerance,
		"swap recurrence matches copy-based reference within tolerance");

	const std::size_t fullHierarchyBytes =
		static_cast<std::size_t>(hierarchySize) * Param::N2 * sizeof(Complex);
	const std::size_t expectedCopyCount=2;
	const std::size_t previousCopyCount=expectedCopyCount + static_cast<std::size_t>(integrationOrder);
	const std::size_t expectedCopyBytes=expectedCopyCount * fullHierarchyBytes;
	const std::size_t previousCopyBytes=previousCopyCount * fullHierarchyBytes;
	std::cout << "integrator_d2d_copy_reduction: d2d_copy_count="
			  << profilingSnapshot.d2dCopy.copyCount.value_or(0)
			  << " d2d_copy_bytes=" << profilingSnapshot.d2dCopy.bytes.value_or(0)
			  << " previous_copy_count=" << previousCopyCount
			  << " previous_copy_bytes=" << previousCopyBytes
			  << " integrator_order_count=" << integrationOrder
			  << " reference=swap recurrence removes one full-buffer D2D copy per integration order"
			  << '\n';
	test.expect(
		profilingSnapshot.d2dCopy.copyCount.value_or(0) == expectedCopyCount,
		"swap recurrence records only initial and final full hierarchy D2D copies");
	test.expect(
		profilingSnapshot.d2dCopy.bytes.value_or(0) == expectedCopyBytes,
		"swap recurrence records full hierarchy D2D copy bytes");

	const helix::test::DiffStats traceDiff = helix::test::compareScalar(
		helix::test::traceBlock(actual, Param::N, 0),
		helix::test::ComplexScalar{1.0, 0.0});
	helix::test::printDiffStats(
		std::cout,
		"integrator_swap_trace",
		traceDiff,
		kAbsTolerance,
		kRelTolerance,
		"unit trace after default-order recurrence");
	test.expect(
		traceDiff.maxAbs <= kAbsTolerance,
		"default-order recurrence reduced trace remains one within tolerance");

	cleanupRuntime();
}

void testOneStepRepeatabilityAndInvariants(helix::test::Reporter& test)
{
	Param::IntegrationNum = 1;
	initialize();
	printReferenceInput();

	const thrust::host_vector<Complex> initial = dRho;
	test.expect(helix::test::allFinite(initial), "initial rho values are finite");
	expectReducedDensityInvariants(test, initial, "initial_trace", "initial_hermiticity");

	helix::library::BackendProfilingCounters profilingSnapshot;
	{
		helix::library::ScopedBackendProfiling profiling;
		develop();
		test.expect(cudaDeviceSynchronize() == cudaSuccess, "first one-step develop completes");
		profilingSnapshot = profiling.snapshot();
	}
	const std::size_t expectedSpmmCalls = static_cast<std::size_t>(hierarchySize)
		* expectedSpmmCallsPerHierarchyBlock()
		* static_cast<std::size_t>(Param::IntegrationNum);
	std::cout << "one_step_h_diagonal_elementwise_spmm_calls: actual="
			  << profilingSnapshot.spmm.callCount.value_or(0)
			  << " expected=" << expectedSpmmCalls
			  << " reference=H_DIAGONAL elementwise path leaves only V-path SpMM calls" << '\n';
	test.expect(
		profilingSnapshot.spmm.callCount.value_or(0) == expectedSpmmCalls,
		"one-step H diagonal specialization removes H-path SpMM calls");
	const thrust::host_vector<Complex> first = dRho;
	test.expect(helix::test::allFinite(first), "first one-step rho values are finite");
	expectReducedDensityInvariants(test, first, "one_step_trace", "one_step_hermiticity");

	dRho = initial;
	develop();
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "second one-step develop completes");
	const thrust::host_vector<Complex> second = dRho;
	test.expect(helix::test::allFinite(second), "second one-step rho values are finite");

	const helix::test::DiffStats repeatDiff = helix::test::vectorDiff(second, first);
	helix::test::printDiffStats(
		std::cout,
		"one_step_repeatability",
		repeatDiff,
		kAbsTolerance,
		kRelTolerance,
		"same-process repeated one-step from identical initial rho");
	test.expect(
		repeatDiff.maxAbs <= kAbsTolerance && repeatDiff.maxRel <= kRelTolerance,
		"same-process repeated one-step is reproducible within tolerance");

	cleanupRuntime();
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testIntegratorSwapMatchesCopyReferenceAndRecordsD2D(test);
	testOneStepRepeatabilityAndInvariants(test);

	return test.finish("one-step evolution tests");
}
