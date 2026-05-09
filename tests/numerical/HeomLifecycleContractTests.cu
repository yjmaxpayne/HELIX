#include "Parameters.h"
#include "support/Assert.h"
#include "support/LegacyHeomRun.h"
#include "support/NumericalInvariants.h"

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

struct LifecycleSnapshot
{
	thrust::host_vector<Complex> reducedDensity;
};

void printContractInput()
{
	std::cout << "lifecycle_contract_input: precision=" << kPrecision
			  << " system_size=" << Param::N
			  << " step=" << Param::Step
			  << " integration_order=1"
			  << " run_steps=1"
			  << " contract=create/run/destroy/recreate"
			  << '\n';
}

LifecycleSnapshot createRunDestroyOnce(
	helix::test::Reporter& test,
	const helix::test::HeomContextConfig& config,
	const char* runName)
{
	helix::test::LegacyHeomRun run(config);
	run.create();
	run.run();

	LifecycleSnapshot snapshot{run.reducedDensityBlock()};
	test.expect(
		helix::test::allFinite(snapshot.reducedDensity),
		std::string(runName) + " reduced density values are finite");

	const helix::test::DiffStats traceDiff = helix::test::compareScalar(
		helix::test::traceBlock(snapshot.reducedDensity, Param::N, 0),
		helix::test::ComplexScalar{1.0, 0.0});
	helix::test::printDiffStats(
		std::cout,
		runName,
		traceDiff,
		kAbsTolerance,
		kRelTolerance,
		"unit trace after lifecycle run");
	test.expect(
		traceDiff.maxAbs <= kAbsTolerance && traceDiff.maxRel <= kRelTolerance,
		std::string(runName) + " reduced trace remains one within tolerance");

	run.destroy();
	test.expect(
		helix::test::legacyHeomStorageReleased(),
		std::string(runName) + " destroy releases legacy matrix storage and cuBLAS handle");

	return snapshot;
}

void testCreateRunDestroyRecreate(helix::test::Reporter& test)
{
	helix::test::HeomContextConfig config;
	config.integrationOrder = 1;
	config.stepCount = 1;

	printContractInput();
	const LifecycleSnapshot first = createRunDestroyOnce(test, config, "lifecycle_first_run");
	const LifecycleSnapshot second = createRunDestroyOnce(test, config, "lifecycle_second_run");

	const helix::test::DiffStats repeatDiff = helix::test::vectorDiff(
		second.reducedDensity,
		first.reducedDensity);
	helix::test::printDiffStats(
		std::cout,
		"lifecycle_recreate_repeatability",
		repeatDiff,
		kAbsTolerance,
		kRelTolerance,
		"same-process create/run/destroy/recreate reduced density block");
	test.expect(
		repeatDiff.maxAbs <= kAbsTolerance && repeatDiff.maxRel <= kRelTolerance,
		"same-process recreate run is reproducible within tolerance");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testCreateRunDestroyRecreate(test);

	return test.finish("HEOM lifecycle contract tests");
}
