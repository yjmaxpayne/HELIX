#include <helix/helix.h>
#include <helix/examples.h>

#include "parameters.h"
#include "support/assert.h"
#include "support/legacy_heom_run.h"
#include "support/temp_dir.h"

#include <algorithm>
#include <cmath>
#include <complex>
#include <filesystem>
#include <iostream>
#include <string>
#include <system_error>
#include <utility>
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

class CurrentPathGuard {
public:
	explicit CurrentPathGuard(std::filesystem::path target)
		: previous_(std::filesystem::current_path())
	{
		std::filesystem::current_path(std::move(target));
	}

	~CurrentPathGuard()
	{
		std::error_code error;
		std::filesystem::current_path(previous_, error);
	}

	CurrentPathGuard(const CurrentPathGuard&) = delete;
	CurrentPathGuard& operator=(const CurrentPathGuard&) = delete;

private:
	std::filesystem::path previous_;
};

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

DiffStats hermiticityDiff(const Density& values)
{
	DiffStats stats;
	for(int row = 0; row < Param::N; ++row)
	{
		for(int column = 0; column < Param::N; ++column)
		{
			const auto& lhs = values[static_cast<std::size_t>(row) * Param::N + column];
			const auto& rhs = values[static_cast<std::size_t>(column) * Param::N + row];
			const double absDiff = std::abs(lhs - std::conj(rhs));
			const double referenceScale = std::max(std::abs(lhs), std::abs(rhs));
			updateDiffStats(stats, absDiff, referenceScale);
		}
	}
	return stats;
}

void printDiffStats(const char* name, const DiffStats& stats, const char* reference)
{
	std::cout << name << ": max_abs_diff=" << stats.maxAbs
			  << " max_rel_diff=" << stats.maxRel
			  << " abs_tolerance=" << kAbsTolerance
			  << " rel_tolerance=" << kRelTolerance
			  << " reference=" << reference << '\n';
}

bool hasPrefix(const std::string& value, const char* prefix)
{
	return value.rfind(prefix, 0) == 0;
}

bool isLegacyOutputName(const std::filesystem::path& path)
{
	const std::string name = path.filename().string();
	return name == "outputEnergy.txt"
		|| name == "output.txt"
		|| (hasPrefix(name, "output_rho") && path.extension() == ".txt")
		|| (hasPrefix(name, "snapshot_rho") && path.extension() == ".dat");
}

bool containsLegacyOutput(const std::filesystem::path& directory)
{
	for(const auto& entry : std::filesystem::directory_iterator(directory))
	{
		if(isLegacyOutputName(entry.path()))
		{
			std::cerr << "unexpected legacy output file: " << entry.path() << '\n';
			return true;
		}
	}
	return false;
}

helix::RunResult runDefaultSpinGlassSmoke(std::size_t steps)
{
	helix::ContextOptions contextOptions;
	contextOptions.integrationOrder = 1;
	contextOptions.timeStep = Param::Step;

	helix::Context context(contextOptions);
	auto system = helix::examples::legacy_spin_glass_system();
	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);

	helix::SolverOptions solverOptions;
	solverOptions.timeStep = Param::Step;
	helix::HEOMSolver solver(context, system, bath, hierarchy, solverOptions);

	auto result = solver.run_steps(steps);
	context.destroy();
	return result;
}

void test_run_result_shape_diagnostics_and_no_file_output(helix::test::Reporter& test)
{
	constexpr std::size_t kSteps = 1;
	helix::test::TempDir temp("helix-result-shape-");
	helix::RunResult result;

	std::cout << "public_result_shape_input: precision=" << kPrecision
			  << " system_size=" << Param::N
			  << " step=" << Param::Step
			  << " integration_order=1"
			  << " run_steps=" << kSteps
			  << " contract=RunResult final reduced density and no-file-output"
			  << '\n';

	{
		CurrentPathGuard cwd(temp.path());
		result = runDefaultSpinGlassSmoke(kSteps);
	}

	test.expect(result.ok(), "RunResult reports clean diagnostics for default spin-glass smoke");
	test.expect(result.reduced_density_shape.count == 1, "default FinalState result reports one state");
	test.expect(result.reduced_density_shape.rows == static_cast<std::size_t>(Param::N),
		"reduced density shape rows match Param::N");
	test.expect(result.reduced_density_shape.cols == static_cast<std::size_t>(Param::N),
		"reduced density shape cols match Param::N");
	test.expect(result.reduced_density_shape.storageOrder == helix::MatrixStorageOrder::RowMajor,
		"reduced density shape records row-major storage");
	test.expect(result.times.size() == result.reduced_density_shape.count,
		"RunResult times count matches reduced density state count");
	test.expect(result.reduced_density.size()
			== result.reduced_density_shape.count
				* result.reduced_density_shape.rows
				* result.reduced_density_shape.cols,
		"RunResult reduced density buffer size matches shape");
	test.expect(!result.times.empty() && std::abs(result.times.front() - kSteps * Param::Step) <= kAbsTolerance,
		"RunResult final time is steps times dt");

	test.expect(allFinite(result.reduced_density), "RunResult reduced density values are finite");

	const DiffStats traceDiff = vectorDiff({traceBlock(result.reduced_density)}, {{1.0, 0.0}});
	printDiffStats("public_result_trace", traceDiff, "unit trace after public RunResult extraction");
	test.expect(traceDiff.maxAbs <= kAbsTolerance && traceDiff.maxRel <= kRelTolerance,
		"RunResult reduced density trace remains one within tolerance");

	const DiffStats hermiticity = hermiticityDiff(result.reduced_density);
	printDiffStats("public_result_hermiticity", hermiticity, "Hermiticity after public RunResult extraction");
	test.expect(hermiticity.maxAbs <= kAbsTolerance && hermiticity.maxRel <= kRelTolerance,
		"RunResult reduced density remains Hermitian within tolerance");

	test.expect(result.diagnostics.backend == helix::Backend::LegacyCudaSparse,
		"RunResult diagnostics record backend");
	test.expect(result.diagnostics.precision == helix::Precision::Single,
		"RunResult diagnostics record precision");
	test.expect(result.diagnostics.hilbertSize == static_cast<std::size_t>(Param::N),
		"RunResult diagnostics record Hilbert size");
	test.expect(result.diagnostics.hierarchySize > 0,
		"RunResult diagnostics record hierarchy size");
	test.expect(result.diagnostics.steps == kSteps,
		"RunResult diagnostics record step count");
	test.expect(std::abs(result.diagnostics.timeStep - Param::Step) <= kAbsTolerance,
		"RunResult diagnostics record dt");
	test.expect(result.diagnostics.integrationOrder == 1,
		"RunResult diagnostics record integration order");
	test.expect(result.diagnostics.status == helix::RunStatus::Success,
		"RunResult diagnostics record successful status");
	test.expect(result.diagnostics.warnings.empty(),
		"RunResult diagnostics expose warnings and default smoke has none");

	test.expect(!containsLegacyOutput(temp.path()),
		"core library solver run does not write legacy CLI output files in the current working directory");
	test.expect(helix::test::legacyHeomStorageReleased(),
		"public result shape smoke releases legacy storage after context destroy");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	test_run_result_shape_diagnostics_and_no_file_output(test);

	return test.finish("public RunResult shape tests");
}
