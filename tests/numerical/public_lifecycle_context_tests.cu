#include <helix/helix.h>

#include "parameters.h"
#include "support/assert.h"
#include "support/legacy_heom_run.h"

#include <algorithm>
#include <cmath>
#include <complex>
#include <iostream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

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

struct DiffStats
{
	double maxAbs = 0.0;
	double maxRel = 0.0;
};

using Density = std::vector<std::complex<double>>;

bool allFinite(const Density& values)
{
	for(const auto& value : values)
	{
		if(!std::isfinite(value.real()) || !std::isfinite(value.imag()))
		{
			return false;
		}
	}
	return true;
}

void updateDiffStats(DiffStats& stats, double absDiff, double referenceScale)
{
	stats.maxAbs = std::max(stats.maxAbs, absDiff);
	if(referenceScale > 0.0)
	{
		stats.maxRel = std::max(stats.maxRel, absDiff / referenceScale);
	}
	else
	{
		stats.maxRel = std::max(stats.maxRel, absDiff);
	}
}

DiffStats vectorDiff(const Density& actual, const Density& expected)
{
	DiffStats stats;
	const std::size_t count = std::min(actual.size(), expected.size());
	for(std::size_t i = 0; i < count; ++i)
	{
		const double absDiff = std::abs(actual[i] - expected[i]);
		const double referenceScale = std::max(std::abs(actual[i]), std::abs(expected[i]));
		updateDiffStats(stats, absDiff, referenceScale);
	}
	if(actual.size() != expected.size())
	{
		updateDiffStats(stats, 1.0, 1.0);
	}
	return stats;
}

std::complex<double> traceBlock(const Density& values)
{
	std::complex<double> trace{0.0, 0.0};
	for(int i = 0; i < Param::N; ++i)
	{
		trace += values[static_cast<std::size_t>(i) * Param::N + i];
	}
	return trace;
}

void printDiffStats(const char* name, const DiffStats& stats, const char* reference)
{
	std::cout << name << ": max_abs_diff=" << stats.maxAbs
			  << " max_rel_diff=" << stats.maxRel
			  << " abs_tolerance=" << kAbsTolerance
			  << " rel_tolerance=" << kRelTolerance
			  << " reference=" << reference << '\n';
}

Density createRunDestroyOnce(helix::test::Reporter& test, const char* runName)
{
	helix::ContextOptions options;
	options.integrationOrder = 1;
	options.timeStep = Param::Step;

	helix::Context context(options);
	context.run_steps(1);
	Density reducedDensity = context.reduced_density();

	test.expect(allFinite(reducedDensity), std::string(runName) + " reduced density values are finite");

	const DiffStats traceDiff = vectorDiff({traceBlock(reducedDensity)}, {{1.0, 0.0}});
	printDiffStats(runName, traceDiff, "unit trace after public Context lifecycle run");
	test.expect(traceDiff.maxAbs <= kAbsTolerance && traceDiff.maxRel <= kRelTolerance,
		std::string(runName) + " reduced trace remains one within tolerance");

	context.destroy();
	test.expect(helix::test::legacyHeomStorageReleased(),
		std::string(runName) + " destroy releases legacy matrix storage and runtime handles");

	return reducedDensity;
}

void test_context_is_move_only(helix::test::Reporter& test)
{
	test.expect(!std::is_copy_constructible<helix::Context>::value, "Context is not copy constructible");
	test.expect(!std::is_copy_assignable<helix::Context>::value, "Context is not copy assignable");
	test.expect(std::is_move_constructible<helix::Context>::value, "Context is move constructible");
	test.expect(std::is_move_assignable<helix::Context>::value, "Context is move assignable");
}

void test_public_context_create_destroy_recreate(helix::test::Reporter& test)
{
	std::cout << "public_context_lifecycle_input: precision=" << kPrecision
			  << " system_size=" << Param::N
			  << " step=" << Param::Step
			  << " integration_order=1"
			  << " run_steps=1"
			  << " contract=public Context create/run/destroy/recreate"
			  << '\n';

	const Density first = createRunDestroyOnce(test, "public_context_first_run");
	const Density second = createRunDestroyOnce(test, "public_context_second_run");

	const DiffStats repeatDiff = vectorDiff(second, first);
	printDiffStats("public_context_recreate_repeatability",
		repeatDiff,
		"same-process public Context create/run/destroy/recreate reduced density block");
	test.expect(repeatDiff.maxAbs <= kAbsTolerance && repeatDiff.maxRel <= kRelTolerance,
		"public Context recreate run is reproducible within tolerance");
}

void test_nested_context_fails_with_sequential_message(helix::test::Reporter& test)
{
	helix::ContextOptions options;
	options.integrationOrder = 1;

	helix::Context context(options);

	bool threw = false;
	try
	{
		helix::Context nested(options);
		(void)nested;
	}
	catch(const std::logic_error& error)
	{
		threw = true;
		const std::string message = error.what();
		test.expect(message.find("sequential lifecycle") != std::string::npos,
			"nested Context failure explains v0.1 sequential lifecycle only");
	}

	test.expect(threw, "second active Context construction fails");
	context.destroy();
}

} // namespace

int main()
{
	helix::test::Reporter test;

	test_context_is_move_only(test);
	test_public_context_create_destroy_recreate(test);
	test_nested_context_fails_with_sequential_message(test);

	return test.finish("public lifecycle Context tests");
}
