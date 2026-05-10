#include <helix/helix.h>
#include <helix/examples.h>

#include "parameters.h"
#include "support/assert.h"
#include "support/legacy_heom_run.h"

#include <algorithm>
#include <cmath>
#include <complex>
#include <iostream>
#include <string>
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

using Density = std::vector<std::complex<double>>;

struct DiffStats
{
	double maxAbs = 0.0;
	double maxRel = 0.0;
};

helix::SparseOperator validOperator(std::size_t dimension)
{
	helix::SparseOperator op;
	op.rows = dimension;
	op.cols = dimension;
	op.rowOffsets.reserve(dimension + 1);
	for(std::size_t i = 0; i <= dimension; ++i)
	{
		op.rowOffsets.push_back(i);
	}
	for(std::size_t i = 0; i < dimension; ++i)
	{
		op.columnIndices.push_back(i);
		op.values.push_back({1.0, 0.0});
	}
	return op;
}

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

helix::ContextOptions smokeContextOptions()
{
	helix::ContextOptions options;
	options.integrationOrder = 1;
	options.timeStep = Param::Step;
	return options;
}

void test_public_solver_runs_legacy_spin_glass_adapter(helix::test::Reporter& test)
{
	std::cout << "public_solver_spin_glass_input: precision=" << kPrecision
			  << " system_size=" << Param::N
			  << " step=" << Param::Step
			  << " integration_order=1"
			  << " run_steps=2"
			  << " contract=public HEOMSolver legacy spin-glass adapter"
			  << '\n';

	helix::Context context(smokeContextOptions());
	auto system = helix::examples::legacy_spin_glass_system();
	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);
	helix::SolverOptions solverOptions;
	helix::HEOMSolver solver(context, system, bath, hierarchy, solverOptions);

	auto result = solver.run_steps(2);

	test.expect(result.ok(), "public HEOMSolver spin-glass smoke run returns clean diagnostics");
	test.expect(result.reducedDensity.size() == static_cast<std::size_t>(Param::N2),
		"public HEOMSolver spin-glass smoke exposes the reduced density block");
	test.expect(allFinite(result.reducedDensity), "public HEOMSolver spin-glass reduced density is finite");

	const DiffStats traceDiff = vectorDiff({traceBlock(result.reducedDensity)}, {{1.0, 0.0}});
	printDiffStats("public_solver_spin_glass_trace",
		traceDiff,
		"unit trace after public HEOMSolver two-step legacy adapter run");
	test.expect(traceDiff.maxAbs <= kAbsTolerance && traceDiff.maxRel <= kRelTolerance,
		"public HEOMSolver spin-glass trace remains one within tolerance");

	context.destroy();
	test.expect(helix::test::legacyHeomStorageReleased(),
		"public HEOMSolver context destroy releases legacy storage");
}

void test_sparse_system_does_not_run_hard_coded_legacy_adapter(helix::test::Reporter& test)
{
	helix::Context context(smokeContextOptions());
	const Density before = context.reduced_density();

	auto sparseSystem = helix::System::from_sparse(validOperator(2), {});
	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);
	helix::HEOMSolver solver(context, sparseSystem, bath, hierarchy, helix::SolverOptions{});

	auto result = solver.run_steps(1);
	const Density after = context.reduced_density();

	test.expect(!result.ok(), "arbitrary sparse system is not accepted by the legacy adapter path");
	test.expect(result.diagnostics.hasError(helix::StatusCode::UnsupportedExecution),
		"arbitrary sparse system reports unsupported execution");

	const DiffStats noRunDiff = vectorDiff(after, before);
	printDiffStats("public_solver_sparse_rejected_no_run",
		noRunDiff,
		"arbitrary sparse execution must not advance the hard-coded legacy runtime");
	test.expect(noRunDiff.maxAbs == 0.0 && noRunDiff.maxRel == 0.0,
		"arbitrary sparse rejection leaves the active legacy context unchanged");

	context.destroy();
}

} // namespace

int main()
{
	helix::test::Reporter test;

	test_public_solver_runs_legacy_spin_glass_adapter(test);
	test_sparse_system_does_not_run_hard_coded_legacy_adapter(test);

	return test.finish("public HEOMSolver spin-glass tests");
}
