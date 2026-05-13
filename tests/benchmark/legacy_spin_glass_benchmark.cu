#include <helix/helix.h>
#include <helix/examples.h>
#include <helix/version.h>

#include "support/benchmark_artifacts.h"
#include "support/benchmark_schema.h"
#include "support/temp_dir.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace {

constexpr std::size_t kWarmupSteps = 1;
constexpr std::size_t kSteadySteps = 1;
constexpr int kDevice = 0;

struct UtcTimestamp
{
	std::string iso;
	std::string compact;
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

class DeviceMemoryTracker {
public:
	void capture()
	{
		std::size_t freeBytes = 0;
		std::size_t totalBytes = 0;
		requireCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "query CUDA memory");
		if(!initialized_)
		{
			initialUsedBytes_ = totalBytes - freeBytes;
			initialized_ = true;
		}
		peakUsedBytes_ = std::max(peakUsedBytes_, totalBytes - freeBytes);
	}

	long long peakDeviceBytes() const noexcept
	{
		return static_cast<long long>(peakUsedBytes_);
	}

	long long deviceDeltaBytes() const noexcept
	{
		return static_cast<long long>(peakUsedBytes_ - initialUsedBytes_);
	}

private:
	static void requireCuda(cudaError_t status, const char* action)
	{
		if(status != cudaSuccess)
		{
			throw std::runtime_error(std::string("Failed to ") + action + ": " + cudaGetErrorString(status));
		}
	}

	bool initialized_ = false;
	std::size_t initialUsedBytes_ = 0;
	std::size_t peakUsedBytes_ = 0;
};

void requireCuda(cudaError_t status, const char* action)
{
	if(status != cudaSuccess)
	{
		throw std::runtime_error(std::string("Failed to ") + action + ": " + cudaGetErrorString(status));
	}
}

UtcTimestamp makeTimestamp()
{
	const std::time_t now = std::time(nullptr);
	std::tm utc{};
#if defined(_WIN32)
	gmtime_s(&utc, &now);
#else
	gmtime_r(&now, &utc);
#endif

	std::ostringstream iso;
	iso << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");

	std::ostringstream compact;
	compact << std::put_time(&utc, "%Y%m%dT%H%M%SZ");

	return {iso.str(), compact.str()};
}

template <typename Fn>
double measureCudaPhase(DeviceMemoryTracker& memory, Fn&& fn)
{
	requireCuda(cudaDeviceSynchronize(), "synchronize before benchmark phase");
	memory.capture();
	const auto start = std::chrono::steady_clock::now();
	fn();
	requireCuda(cudaDeviceSynchronize(), "synchronize after benchmark phase");
	const auto stop = std::chrono::steady_clock::now();
	memory.capture();
	return std::chrono::duration<double, std::milli>(stop - start).count();
}

std::string cudaVersionString(int version)
{
	std::ostringstream output;
	output << version / 1000 << '.' << (version % 1000) / 10;
	return output.str();
}

helix::ContextOptions benchmarkContextOptions()
{
	helix::ContextOptions options;
	options.device = kDevice;
	return options;
}

helix::RunResult runSolverCalibration(const helix::ContextOptions& options, std::size_t steps)
{
	helix::Context context(options);
	auto system = helix::examples::legacy_spin_glass_system();
	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);

	helix::SolverOptions solverOptions;
	solverOptions.steps = steps;
	solverOptions.timeStep = options.timeStep;
	helix::HEOMSolver solver(context, system, bath, hierarchy, solverOptions);

	helix::RunResult result = solver.run_steps(steps);
	context.destroy();
	return result;
}

void require(bool condition, const std::string& message)
{
	if(!condition)
	{
		throw std::runtime_error(message);
	}
}

void validateCalibration(const std::vector<std::complex<double>>& directDensity, const helix::RunResult& result)
{
	require(result.ok(), std::string("HEOMSolver calibration failed: ") + result.diagnostics.summary());
	require(result.reduced_density_shape.count == 1, "HEOMSolver calibration must return one final state");
	require(result.reduced_density_shape.rows > 0, "HEOMSolver calibration rows must be positive");
	require(result.reduced_density_shape.cols > 0, "HEOMSolver calibration cols must be positive");
	require(result.reduced_density.size()
			== result.reduced_density_shape.count
				* result.reduced_density_shape.rows
				* result.reduced_density_shape.cols,
		"HEOMSolver calibration buffer size must match RunResult shape");
	require(directDensity.size() == result.reduced_density.size(),
		"Context reduced_density size must match HEOMSolver RunResult size");
	require(result.diagnostics.status == helix::RunStatus::Success,
		"HEOMSolver calibration diagnostics must report success");
	require(result.diagnostics.steps == kWarmupSteps + kSteadySteps,
		"HEOMSolver calibration diagnostics must mirror benchmark steps");
}

void validateRecord(const helix::test::benchmark::BenchmarkRecord& record)
{
	std::vector<helix::test::benchmark::ValidationError> errors;
	if(helix::test::benchmark::validate(record, errors))
	{
		return;
	}

	std::ostringstream message;
	message << "benchmark record failed schema validation:";
	for(const auto& error : errors)
	{
		message << ' ' << error.path << '=' << error.message << ';';
	}
	throw std::runtime_error(message.str());
}

helix::test::benchmark::BenchmarkRecord makeRecord(const UtcTimestamp& timestamp,
	const cudaDeviceProp& deviceProperties,
	int driverVersion,
	int runtimeVersion,
	const helix::Bath& bath,
	const helix::HierarchySpec& hierarchy,
	const helix::RunResult& calibration,
	const helix::test::benchmark::BenchmarkTiming& timing,
	const helix::test::benchmark::BenchmarkMemory& memory)
{
	using namespace helix::test::benchmark;

	BenchmarkRecord record;
	record.runId = timestamp.compact + "-legacy-spin-glass-sm"
		+ std::to_string(deviceProperties.major) + std::to_string(deviceProperties.minor);
	record.timestampUtc = timestamp.iso;
	record.helix.version = helix::versionString();
	record.helix.versionSource = helix::versionSource();
	record.helix.gitCommit = "unknown";
	record.build.type = HELIX_BENCHMARK_BUILD_TYPE;
	record.build.cudaArchitectures = HELIX_BENCHMARK_CUDA_ARCHITECTURES;
	record.build.compiler = HELIX_BENCHMARK_COMPILER;
	record.host.os = "linux";
	record.host.runner = "ctest_or_manual";
	record.gpu.name = deviceProperties.name;
	record.gpu.device = kDevice;
	record.gpu.driver = cudaVersionString(driverVersion);
	record.gpu.memoryTotalBytes = static_cast<long long>(deviceProperties.totalGlobalMem);
	record.cuda.runtimeVersion = cudaVersionString(runtimeVersion);
	record.cuda.driverVersion = cudaVersionString(driverVersion);
	record.caseInfo.name = "legacy_spin_glass_default";
	record.caseInfo.backend = toString(calibration.diagnostics.backend);
	record.caseInfo.precision = toString(calibration.diagnostics.precision);
	record.caseInfo.resultMode = toString(helix::ResultMode::FinalState);
	record.problem.hilbertSize = calibration.diagnostics.hilbertSize;
	record.problem.kMax = bath.padeTerms;
	record.problem.jMax = hierarchy.maxDepth;
	record.problem.hierarchySize = calibration.diagnostics.hierarchySize;
	record.problem.timeStep = calibration.diagnostics.timeStep;
	record.problem.integrationOrder = calibration.diagnostics.integrationOrder;
	record.problem.steps = kWarmupSteps + kSteadySteps;
	record.problem.warmupSteps = kWarmupSteps;
	record.problem.steadySteps = kSteadySteps;
	record.timing = timing;
	record.memory = memory;
	record.diagnostics = mirrorDiagnostics(calibration.diagnostics);
	record.profiling.instrumentation = {"runner_wall_clock", "cudaDeviceSynchronize_phase_boundaries"};
	record.notes =
		"Context phase timing with HEOMSolver smoke calibration; no legacy CLI output files expected";
	return record;
}

void printSummary(const helix::test::benchmark::BenchmarkRecord& record, const helix::RunResult& calibration)
{
	std::cerr << std::fixed << std::setprecision(3)
			  << "benchmark_summary:"
			  << " case=" << record.caseInfo.name
			  << " backend=" << record.caseInfo.backend
			  << " precision=" << record.caseInfo.precision
			  << " steps=" << record.problem.steps
			  << " hierarchy_size=" << record.problem.hierarchySize
			  << " result_shape=" << calibration.reduced_density_shape.count
			  << "x" << calibration.reduced_density_shape.rows
			  << "x" << calibration.reduced_density_shape.cols
			  << " timing_ms.init=" << record.timing.init
			  << " timing_ms.warmup=" << record.timing.warmup
			  << " timing_ms.steady_propagation=" << record.timing.steadyPropagation
			  << " timing_ms.result_extraction=" << record.timing.resultExtraction
			  << " timing_ms.teardown=" << record.timing.teardown
			  << " memory.peak_device_bytes=" << record.memory.peakDeviceBytes
			  << " memory.device_delta_bytes=" << record.memory.deviceDeltaBytes
			  << '\n';
}

std::string optionalBoolString(const std::optional<bool>& value)
{
	if(!value.has_value())
	{
		return "unknown";
	}
	return *value ? "true" : "false";
}

std::string optionalStringOr(const std::optional<std::string>& value, const std::string& fallback)
{
	if(value.has_value() && !value->empty())
	{
		return *value;
	}
	return fallback;
}

std::string joinStrings(const std::vector<std::string>& values)
{
	if(values.empty())
	{
		return "none";
	}

	std::ostringstream output;
	for(std::size_t i = 0; i < values.size(); ++i)
	{
		if(i != 0)
		{
			output << ", ";
		}
		output << values[i];
	}
	return output.str();
}

std::string markdownSummary(const helix::test::benchmark::BenchmarkRecord& record,
	const helix::RunResult& calibration,
	const helix::test::benchmark::BenchmarkArtifactPaths& artifacts)
{
	std::ostringstream output;
	output << std::fixed << std::setprecision(3)
		   << "# HELIX benchmark summary\n\n"
		   << "This file is a release/PR handoff summary for benchmark trends. It is not a "
			  "correctness gate, and HELIX does not apply a default speed threshold to this "
			  "benchmark.\n\n"
		   << "## Artifacts\n\n"
		   << "- Schema version: `" << record.schemaVersion << "`\n"
		   << "- Artifact root: `" << artifacts.root.string() << "`\n"
		   << "- JSONL: `" << artifacts.jsonl.string() << "`\n"
		   << "- Summary: `" << artifacts.summary.string() << "`\n"
		   << "- Nsight directory: `" << artifacts.nsightDir.string() << "`\n"
		   << "- Retention: benchmark artifacts are separate from ordinary CUDA correctness logs; "
			  "manual or scheduled benchmark workflows should upload only this artifact root.\n\n"
		   << "## Run metadata\n\n"
		   << "| Field | Value |\n"
		   << "| --- | --- |\n"
		   << "| Run ID | `" << record.runId << "` |\n"
		   << "| Timestamp UTC | `" << record.timestampUtc << "` |\n"
		   << "| HELIX version | `" << record.helix.version << "` |\n"
		   << "| Version source | `" << record.helix.versionSource << "` |\n"
		   << "| Git commit | `" << record.helix.gitCommit << "` |\n"
		   << "| Git dirty | `" << optionalBoolString(record.helix.gitDirty) << "` |\n"
		   << "| Build type | `" << record.build.type << "` |\n"
		   << "| CUDA architectures | `" << record.build.cudaArchitectures << "` |\n"
		   << "| Compiler | `" << record.build.compiler << "` |\n"
		   << "| Host OS | `" << record.host.os << "` |\n"
		   << "| Host runner | `" << record.host.runner << "` |\n"
		   << "| GPU | `" << record.gpu.name << "` |\n"
		   << "| GPU device | `" << record.gpu.device << "` |\n"
		   << "| GPU driver | `" << record.gpu.driver << "` |\n"
		   << "| GPU total memory bytes | " << record.gpu.memoryTotalBytes << " |\n"
		   << "| CUDA runtime | `" << record.cuda.runtimeVersion << "` |\n"
		   << "| CUDA driver | `" << record.cuda.driverVersion << "` |\n\n"
		   << "## Case metadata\n\n"
		   << "| Field | Value |\n"
		   << "| --- | --- |\n"
		   << "| Name | `" << record.caseInfo.name << "` |\n"
		   << "| Backend | `" << record.caseInfo.backend << "` |\n"
		   << "| Precision | `" << record.caseInfo.precision << "` |\n"
		   << "| Result mode | `" << record.caseInfo.resultMode << "` |\n"
		   << "| N | " << record.problem.hilbertSize << " |\n"
		   << "| KMax | " << record.problem.kMax << " |\n"
		   << "| JMax | " << record.problem.jMax << " |\n"
		   << "| Hierarchy size | " << record.problem.hierarchySize << " |\n"
		   << "| Time step | " << record.problem.timeStep << " |\n"
		   << "| Integration order | " << record.problem.integrationOrder << " |\n"
		   << "| Steps | " << record.problem.steps << " |\n"
		   << "| Warmup steps | " << record.problem.warmupSteps << " |\n"
		   << "| Steady steps | " << record.problem.steadySteps << " |\n"
		   << "| Result shape | " << calibration.reduced_density_shape.count
		   << " x " << calibration.reduced_density_shape.rows
		   << " x " << calibration.reduced_density_shape.cols << " |\n\n"
		   << "## Timing (ms)\n\n"
		   << "| Phase | Milliseconds | Notes |\n"
		   << "| --- | ---: | --- |\n"
		   << "| Init | " << record.timing.init << " | Context construction |\n"
		   << "| Warmup | " << record.timing.warmup << " | Warmup propagation |\n"
		   << "| Steady propagation | " << record.timing.steadyPropagation << " | "
		   << record.timing.steadyPropagationScope << " |\n"
		   << "| Result extraction | " << record.timing.resultExtraction << " | Final reduced-density copy |\n"
		   << "| Teardown | " << record.timing.teardown << " | Context destruction |\n\n"
		   << "## Memory\n\n"
		   << "| Metric | Value |\n"
		   << "| --- | ---: |\n"
		   << "| Peak device bytes | " << record.memory.peakDeviceBytes << " |\n"
		   << "| Device delta bytes | " << record.memory.deviceDeltaBytes << " |\n"
		   << "| Measurement method | `" << record.memory.measurementMethod << "` |\n\n"
		   << "## Gate status\n\n"
		   << "| Gate | Status | Meaning |\n"
		   << "| --- | --- | --- |\n"
		   << "| Correctness | `" << record.gates.correctnessGateStatus
		   << "` | One of `not_run`, `passed`, or `failed`; benchmark runs default to `not_run`. |\n"
		   << "| Baseline | `" << record.gates.baselineGateStatus
		   << "` | One of `not_run`, `passed`, or `failed`; benchmark runs default to `not_run`. |\n\n"
		   << "## Profiling evidence\n\n"
		   << "- Instrumentation: `" << joinStrings(record.profiling.instrumentation) << "`\n"
		   << "- NVTX enabled: `" << (record.profiling.nvtxEnabled ? "true" : "false") << "`\n"
		   << "- Nsight artifact: `"
		   << optionalStringOr(record.profiling.nsightArtifact, artifacts.nsightDir.string()) << "`\n\n"
		   << "| Hypothesis | Status | Evidence slot |\n"
		   << "| --- | --- | --- |\n"
		   << "| H-001 | pending | Filled by PLAN-T6 profiling evidence slots. |\n"
		   << "| H-002 | pending | Filled by PLAN-T6 profiling evidence slots. |\n"
		   << "| H-003 | pending | Filled by PLAN-T6 profiling evidence slots. |\n"
		   << "| H-004 | pending | Filled by PLAN-T6 profiling evidence slots. |\n"
		   << "| H-005 | pending | Filled by PLAN-T6 profiling evidence slots. |\n\n"
		   << "## Release / PR handoff snippet\n\n"
		   << "- Environment: `" << record.gpu.name << "`, CUDA runtime `"
		   << record.cuda.runtimeVersion << "`, driver `" << record.cuda.driverVersion
		   << "`, build `" << record.build.type << "`, arch `" << record.build.cudaArchitectures << "`.\n"
		   << "- Case: `" << record.caseInfo.name << "` using `" << record.caseInfo.backend
		   << "` / `" << record.caseInfo.precision << "`, N=" << record.problem.hilbertSize
		   << ", KMax=" << record.problem.kMax << ", JMax=" << record.problem.jMax
		   << ", hierarchy=" << record.problem.hierarchySize << ", steps=" << record.problem.steps << ".\n"
		   << "- Phase timing ms: init=" << record.timing.init << ", warmup=" << record.timing.warmup
		   << ", steady=" << record.timing.steadyPropagation << ", extraction="
		   << record.timing.resultExtraction << ", teardown=" << record.timing.teardown << ".\n"
		   << "- Memory: peak_device_bytes=" << record.memory.peakDeviceBytes
		   << ", device_delta_bytes=" << record.memory.deviceDeltaBytes
		   << ", method=`" << record.memory.measurementMethod << "`.\n"
		   << "- Gates: correctness=`" << record.gates.correctnessGateStatus << "`, baseline=`"
		   << record.gates.baselineGateStatus << "`; speed threshold=`none`.\n"
		   << "- Follow-up evidence: H-001..H-005 are pending until profiling evidence capture.\n";
	return output.str();
}

void writeTextFile(const std::filesystem::path& path, const std::string& text, std::ios_base::openmode mode)
{
	std::ofstream output(path, mode);
	if(!output)
	{
		throw std::runtime_error("failed to open benchmark artifact: " + path.string());
	}
	output << text;
	if(!output)
	{
		throw std::runtime_error("failed to write benchmark artifact: " + path.string());
	}
}

void writeArtifacts(const helix::test::benchmark::BenchmarkArtifactPaths& artifacts,
	const helix::test::benchmark::BenchmarkRecord& record,
	const helix::RunResult& calibration)
{
	helix::test::benchmark::ensureArtifactDirectories(artifacts);
	writeTextFile(artifacts.jsonl,
		helix::test::benchmark::toJsonLine(record),
		std::ios::out | std::ios::app);
	writeTextFile(artifacts.summary,
		markdownSummary(record, calibration, artifacts),
		std::ios::out | std::ios::trunc);
}

} // namespace

int main()
{
	try
	{
		const UtcTimestamp timestamp = makeTimestamp();
		requireCuda(cudaSetDevice(kDevice), "select CUDA benchmark device");

		cudaDeviceProp deviceProperties{};
		requireCuda(cudaGetDeviceProperties(&deviceProperties, kDevice), "query CUDA device properties");

		int driverVersion = 0;
		int runtimeVersion = 0;
		requireCuda(cudaDriverGetVersion(&driverVersion), "query CUDA driver version");
		requireCuda(cudaRuntimeGetVersion(&runtimeVersion), "query CUDA runtime version");

		const helix::ContextOptions options = benchmarkContextOptions();
		const helix::Bath bath = helix::Bath::drude_lorentz_pade();
		const helix::HierarchySpec hierarchy = helix::HierarchySpec::compiled_default(bath);
		const std::size_t totalSteps = kWarmupSteps + kSteadySteps;
		const std::string runId = timestamp.compact + "-legacy-spin-glass-sm"
			+ std::to_string(deviceProperties.major) + std::to_string(deviceProperties.minor);
		const auto artifacts = helix::test::benchmark::artifactPathsForRoot(
			helix::test::benchmark::resolveArtifactRoot(
				std::getenv("HELIX_BENCHMARK_OUTPUT_DIR"),
				HELIX_BENCHMARK_DEFAULT_OUTPUT_DIR));
		std::cerr << "benchmark_artifact_root: " << artifacts.root << '\n';
		helix::test::TempDir workspace("helix-" + runId + "-");
		CurrentPathGuard cwd(workspace.path());

		DeviceMemoryTracker memoryTracker;
		std::unique_ptr<helix::Context> context;
		std::vector<std::complex<double>> directDensity;
		helix::test::benchmark::BenchmarkTiming timing;

		timing.init = measureCudaPhase(memoryTracker, [&]() {
			context = std::make_unique<helix::Context>(options);
		});
		timing.warmup = measureCudaPhase(memoryTracker, [&]() {
			context->run_steps(kWarmupSteps);
		});
		timing.steadyPropagation = measureCudaPhase(memoryTracker, [&]() {
			context->run_steps(kSteadySteps);
		});
		timing.resultExtraction = measureCudaPhase(memoryTracker, [&]() {
			directDensity = context->reduced_density();
		});
		timing.teardown = measureCudaPhase(memoryTracker, [&]() {
			context->destroy();
			context.reset();
		});

		const helix::RunResult calibration = runSolverCalibration(options, totalSteps);
		validateCalibration(directDensity, calibration);

		const auto legacyOutputs = helix::test::benchmark::findLegacyOutputs(workspace.path());
		require(legacyOutputs.empty(), "benchmark runner must not write legacy CLI output files");

		helix::test::benchmark::BenchmarkMemory memory;
		memory.peakDeviceBytes = memoryTracker.peakDeviceBytes();
		memory.deviceDeltaBytes = memoryTracker.deviceDeltaBytes();
		memory.measurementMethod = "cudaMemGetInfo_delta";

		const auto record = makeRecord(timestamp,
			deviceProperties,
			driverVersion,
			runtimeVersion,
			bath,
			hierarchy,
			calibration,
			timing,
			memory);
		validateRecord(record);
		writeArtifacts(artifacts, record, calibration);

		const auto misplacedArtifacts =
			helix::test::benchmark::findMisplacedBenchmarkArtifacts(workspace.path(), artifacts.root);
		require(misplacedArtifacts.empty(), "benchmark JSONL/summary must only be written under artifact root");
		require(std::filesystem::exists(artifacts.jsonl), "benchmark JSONL artifact must exist");
		require(std::filesystem::exists(artifacts.summary), "benchmark summary artifact must exist");
		require(std::filesystem::is_directory(artifacts.nsightDir), "benchmark nsight artifact directory must exist");

		std::cout << helix::test::benchmark::toJsonLine(record);
		printSummary(record, calibration);
		return 0;
	}
	catch(const std::exception& error)
	{
		std::cerr << "legacy_spin_glass_benchmark failed: " << error.what() << '\n';
		return 1;
	}
}
