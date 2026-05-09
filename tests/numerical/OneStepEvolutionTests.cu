#include "Initialize.h"
#include "Liouville.h"
#include "Matrixes.h"
#include "Parameters.h"
#include "support/Assert.h"
#include "support/NumericalInvariants.h"

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

void testOneStepRepeatabilityAndInvariants(helix::test::Reporter& test)
{
	Param::IntegrationNum = 1;
	initialize();
	printReferenceInput();

	const thrust::host_vector<Complex> initial = dRho;
	test.expect(helix::test::allFinite(initial), "initial rho values are finite");
	expectReducedDensityInvariants(test, initial, "initial_trace", "initial_hermiticity");

	develop();
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "first one-step develop completes");
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

	testOneStepRepeatabilityAndInvariants(test);

	return test.finish("one-step evolution tests");
}
