#include <helix/helix.h>
#include <helix/examples.h>
#include <helix/version.h>

#include "library/backend_profiling.h"
#include "legacy_compile_options.h"
#include "support/benchmark_artifacts.h"
#include "support/benchmark_schema.h"
#include "support/temp_dir.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace {

constexpr std::size_t kDefaultWarmupSteps = 1;
constexpr std::size_t kDefaultSteadySteps = 1;
constexpr int kDevice = 0;

struct UtcTimestamp
{
	std::string iso;
	std::string compact;
};

struct MeasurementResult
{
	helix::Diagnostics diagnostics;
	helix::ReducedDensityShape reducedDensityShape;
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

std::optional<std::string> optionalEnv(const char* name)
{
	const char* value = std::getenv(name);
	if(value == nullptr || value[0] == '\0')
	{
		return std::nullopt;
	}
	return std::string(value);
}

std::string envOrDefault(const char* name, std::string fallback)
{
	const auto value = optionalEnv(name);
	return value.value_or(std::move(fallback));
}

bool envBoolOrDefault(const char* name, bool fallback)
{
	const auto value = optionalEnv(name);
	if(!value.has_value())
	{
		return fallback;
	}
	if(*value == "1" || *value == "true" || *value == "yes" || *value == "on")
	{
		return true;
	}
	if(*value == "0" || *value == "false" || *value == "no" || *value == "off")
	{
		return false;
	}
	throw std::runtime_error(std::string("unsupported boolean environment value for ") + name
		+ ": use 1/0, true/false, yes/no, or on/off");
}

std::optional<bool> optionalBoolEnv(const char* name)
{
	const auto value = optionalEnv(name);
	if(!value.has_value())
	{
		return std::nullopt;
	}
	return envBoolOrDefault(name, false);
}

std::size_t positiveSizeEnvOrDefault(const char* name, std::size_t fallback)
{
	const auto value = optionalEnv(name);
	if(!value.has_value())
	{
		return fallback;
	}

	if(value->front() == '-' || value->front() == '+')
	{
		throw std::runtime_error(std::string("unsupported step count for ") + name
			+ ": use a positive integer");
	}
	std::size_t parsedCharacters = 0;
	const unsigned long long parsed = std::stoull(*value, &parsedCharacters);
	if(parsedCharacters != value->size()
		|| parsed == 0
		|| parsed > static_cast<unsigned long long>(std::numeric_limits<std::size_t>::max()))
	{
		throw std::runtime_error(std::string("unsupported step count for ") + name
			+ ": use a positive integer");
	}
	return static_cast<std::size_t>(parsed);
}

bool cusparseReusePlanEnabledFromEnv()
{
	const auto value = optionalEnv("HELIX_CUSPARSE_REUSE_PLAN");
	if(!value.has_value())
	{
		return true;
	}
	return !(*value == "0"
		|| *value == "false"
		|| *value == "False"
		|| *value == "FALSE"
		|| *value == "off"
		|| *value == "OFF"
		|| *value == "no"
		|| *value == "NO"
		|| *value == "legacy");
}

const char* timingModeName(bool collectBackendProfiling) noexcept
{
	return collectBackendProfiling ? "attribution" : "pure_timing";
}

void require(bool condition, const std::string& message)
{
	if(!condition)
	{
		throw std::runtime_error(message);
	}
}

std::size_t hierarchySizeFor(std::size_t modeCount, std::size_t maxLevel)
{
	if(modeCount == 0 || maxLevel == 0)
	{
		return 0;
	}
	if(modeCount == 1)
	{
		return maxLevel;
	}

	std::size_t total = 0;
	for(std::size_t level = 0; level < maxLevel; ++level)
	{
		total += hierarchySizeFor(modeCount - 1, maxLevel - level);
	}
	return total;
}

MeasurementResult makeMainMeasurementResult(const helix::ContextOptions& options,
	const helix::HierarchySpec& hierarchy,
	const std::vector<std::complex<double>>& directDensity,
	std::size_t steps)
{
	const auto side = static_cast<std::size_t>(
		std::llround(std::sqrt(static_cast<double>(directDensity.size()))));
	require(side > 0, "main measurement reduced density must not be empty");
	require(side * side == directDensity.size(), "main measurement reduced density must be a square matrix");

	MeasurementResult result;
	result.diagnostics.backend = options.backend;
	result.diagnostics.precision = options.precision;
	result.diagnostics.hilbertSize = side;
	result.diagnostics.hierarchySize = hierarchySizeFor(hierarchy.exponentialTerms, hierarchy.maxDepth);
	result.diagnostics.steps = steps;
	result.diagnostics.timeStep = options.timeStep;
	result.diagnostics.integrationOrder = options.integrationOrder;
	result.diagnostics.status = helix::RunStatus::Success;
	result.reducedDensityShape.count = 1;
	result.reducedDensityShape.rows = side;
	result.reducedDensityShape.cols = side;
	result.reducedDensityShape.storageOrder = helix::MatrixStorageOrder::RowMajor;
	return result;
}

void validateCalibration(const std::vector<std::complex<double>>& directDensity,
	const helix::RunResult& result,
	std::size_t totalSteps)
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
	require(result.diagnostics.steps == totalSteps,
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

helix::test::benchmark::BenchmarkProfilingCounters benchmarkCountersFromSnapshot(
	const helix::library::BackendProfilingCounters& snapshot)
{
	using namespace helix::test::benchmark;

	const auto doubleCounter = [](const std::optional<double>& value, const char* unit) {
		return value.has_value() ? collectedCounter(*value, unit) : notCollectedCounter(unit);
	};
	const auto sizeCounter = [](const std::optional<std::size_t>& value, const char* unit) {
		return value.has_value()
			? collectedCounter(static_cast<long long>(*value), unit)
			: notCollectedCounter(unit);
	};

	BenchmarkProfilingCounters counters;
	counters.spmm.callCount = sizeCounter(snapshot.spmm.callCount, "count");
	counters.spmm.timeMs = doubleCounter(snapshot.spmm.timeMs, "ms");
	counters.spmm.descriptorCreateCount = sizeCounter(snapshot.spmm.descriptorCreateCount, "count");
	counters.spmm.workspaceAllocCount = sizeCounter(snapshot.spmm.workspaceAllocCount, "count");
	counters.spmm.workspaceBytes = sizeCounter(snapshot.spmm.workspaceBytes, "bytes");
	counters.spmm.bufferSizeQueryCount = sizeCounter(snapshot.spmm.bufferSizeQueryCount, "count");

	counters.transpose.callCount = sizeCounter(snapshot.transpose.callCount, "count");
	counters.transpose.timeMs = doubleCounter(snapshot.transpose.timeMs, "ms");
	counters.transpose.bytes = sizeCounter(snapshot.transpose.bytes, "bytes");

	counters.d2dCopy.copyCount = sizeCounter(snapshot.d2dCopy.copyCount, "count");
	counters.d2dCopy.timeMs = doubleCounter(snapshot.d2dCopy.timeMs, "ms");
	counters.d2dCopy.bytes = sizeCounter(snapshot.d2dCopy.bytes, "bytes");

	counters.sync.deviceSynchronizeCount = sizeCounter(snapshot.sync.deviceSynchronizeCount, "count");
	counters.sync.syncWaitMs = doubleCounter(snapshot.sync.syncWaitMs, "ms");

	counters.resultExtraction.syncWaitMs = doubleCounter(snapshot.resultExtraction.syncWaitMs, "ms");
	counters.resultExtraction.hostAllocationMs =
		doubleCounter(snapshot.resultExtraction.hostAllocationMs, "ms");
	counters.resultExtraction.d2hCopyMs = doubleCounter(snapshot.resultExtraction.d2hCopyMs, "ms");
	counters.resultExtraction.conversionMs = doubleCounter(snapshot.resultExtraction.conversionMs, "ms");
	counters.resultExtraction.d2hBytes = sizeCounter(snapshot.resultExtraction.d2hBytes, "bytes");
	counters.resultExtraction.elementCount = sizeCounter(snapshot.resultExtraction.elementCount, "count");

	return counters;
}

helix::test::benchmark::BenchmarkRecord makeRecord(const UtcTimestamp& timestamp,
	const cudaDeviceProp& deviceProperties,
	int driverVersion,
	int runtimeVersion,
	const helix::Bath& bath,
	const helix::HierarchySpec& hierarchy,
	const MeasurementResult& mainMeasurement,
	std::size_t warmupSteps,
	std::size_t steadySteps,
	bool calibrationCaptured,
	const helix::test::benchmark::BenchmarkTiming& timing,
	const helix::test::benchmark::BenchmarkMemory& memory,
	const helix::test::benchmark::BenchmarkProfilingCounters& profilingCounters,
	bool collectBackendProfiling,
	const std::optional<std::string>& nsightArtifact)
{
	using namespace helix::test::benchmark;

	BenchmarkRecord record;
	record.runId = timestamp.compact + "-legacy-spin-glass-sm"
		+ std::to_string(deviceProperties.major) + std::to_string(deviceProperties.minor);
	record.timestampUtc = timestamp.iso;
	record.helix.version = helix::versionString();
	record.helix.versionSource = helix::versionSource();
	record.helix.gitCommit = envOrDefault("HELIX_BENCHMARK_GIT_COMMIT", "unknown");
	record.helix.gitDirty = optionalBoolEnv("HELIX_BENCHMARK_GIT_DIRTY");
	record.build.type = HELIX_BENCHMARK_BUILD_TYPE;
	record.build.cudaArchitectures = HELIX_BENCHMARK_CUDA_ARCHITECTURES;
	record.build.compiler = HELIX_BENCHMARK_COMPILER;
	record.host.os = "linux";
	record.host.runner = envOrDefault("HELIX_BENCHMARK_HOST_RUNNER", "ctest_or_manual");
	record.gpu.name = deviceProperties.name;
	record.gpu.device = kDevice;
	record.gpu.driver = cudaVersionString(driverVersion);
	record.gpu.memoryTotalBytes = static_cast<long long>(deviceProperties.totalGlobalMem);
	record.cuda.runtimeVersion = cudaVersionString(runtimeVersion);
	record.cuda.driverVersion = cudaVersionString(driverVersion);
	record.caseInfo.name = "legacy_spin_glass_default";
	record.caseInfo.backend = toString(mainMeasurement.diagnostics.backend);
	record.caseInfo.precision = toString(mainMeasurement.diagnostics.precision);
	record.caseInfo.resultMode = toString(helix::ResultMode::FinalState);
	record.problem.hilbertSize = mainMeasurement.diagnostics.hilbertSize;
	record.problem.kMax = bath.padeTerms;
	record.problem.jMax = hierarchy.maxDepth;
	record.problem.hierarchySize = mainMeasurement.diagnostics.hierarchySize;
	record.problem.timeStep = mainMeasurement.diagnostics.timeStep;
	record.problem.integrationOrder = mainMeasurement.diagnostics.integrationOrder;
	record.problem.steps = warmupSteps + steadySteps;
	record.problem.warmupSteps = warmupSteps;
	record.problem.steadySteps = steadySteps;
	record.timing = timing;
	record.measurementScopes.calibrationCaptured = calibrationCaptured;
	record.measurementScopes.calibrationStatus = calibrationCaptured ? "captured" : "not_captured";
	record.measurementScopes.calibrationExcludedFromMain = true;
	record.memory = memory;
	record.diagnostics = mirrorDiagnostics(mainMeasurement.diagnostics);
	record.gates.correctnessGateStatus = envOrDefault("HELIX_BENCHMARK_CORRECTNESS_GATE_STATUS", "not_run");
	record.gates.baselineGateStatus = envOrDefault("HELIX_BENCHMARK_BASELINE_GATE_STATUS", "not_run");
	record.profiling.timingMode = timingModeName(collectBackendProfiling);
	record.profiling.instrumentation = {"runner_wall_clock", "cudaDeviceSynchronize_phase_boundaries"};
	if(collectBackendProfiling)
	{
		record.profiling.instrumentation.push_back("backend_profiling_counters");
	}
	if(nsightArtifact.has_value())
	{
		record.profiling.instrumentation.push_back("nsight_systems");
		record.profiling.nsightArtifact = nsightArtifact;
	}
	record.profiling.counters = profilingCounters;
	record.profiling.hypotheses =
		defaultProfilingEvidenceSlots(record.timing, record.memory, record.profiling.counters);
	record.notes =
		calibrationCaptured
		? std::string("Context phase timing with HEOMSolver smoke calibration; timing_mode=")
			+ record.profiling.timingMode
			+ "; calibration excluded from main aggregation; no legacy CLI output files expected"
		: std::string("Context phase timing without HEOMSolver smoke calibration; timing_mode=")
			+ record.profiling.timingMode
			+ "; main-only artifact; no legacy CLI output files expected";
	return record;
}

void printSummary(const helix::test::benchmark::BenchmarkRecord& record, const MeasurementResult& mainMeasurement)
{
	std::cerr << std::fixed << std::setprecision(3)
			  << "benchmark_summary:"
			  << " case=" << record.caseInfo.name
			  << " backend=" << record.caseInfo.backend
			  << " precision=" << record.caseInfo.precision
			  << " steps=" << record.problem.steps
			  << " hierarchy_size=" << record.problem.hierarchySize
			  << " result_shape=" << mainMeasurement.reducedDensityShape.count
			  << "x" << mainMeasurement.reducedDensityShape.rows
			  << "x" << mainMeasurement.reducedDensityShape.cols
			  << " main_measurement_scope=" << record.measurementScopes.mainMeasurementScope
			  << " calibration_scope=" << record.measurementScopes.calibrationScope
			  << " calibration_captured=" << (record.measurementScopes.calibrationCaptured ? "true" : "false")
			  << " calibration_excluded_from_main="
			  << (record.measurementScopes.calibrationExcludedFromMain ? "true" : "false")
			  << " timing_mode=" << record.profiling.timingMode
			  << " timing_ms.init=" << record.timing.init
			  << " timing_ms.warmup=" << record.timing.warmup
			  << " timing_ms.steady_propagation=" << record.timing.steadyPropagation
			  << " timing_ms.result_extraction=" << record.timing.resultExtraction
			  << " timing_ms.teardown=" << record.timing.teardown
			  << " profiling.result_extraction.sync_wait_ms="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.syncWaitMs)
			  << " profiling.result_extraction.host_allocation_ms="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.hostAllocationMs)
			  << " profiling.result_extraction.d2h_copy_ms="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.d2hCopyMs)
			  << " profiling.result_extraction.conversion_ms="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.conversionMs)
			  << " profiling.result_extraction.d2h_bytes="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.d2hBytes)
			  << " profiling.result_extraction.element_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.elementCount)
			  << " profiling.spmm.call_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount)
			  << " profiling.spmm.descriptor_create_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.descriptorCreateCount)
			  << " profiling.spmm.workspace_alloc_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.workspaceAllocCount)
			  << " profiling.spmm.workspace_bytes="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.workspaceBytes)
			  << " profiling.spmm.buffer_size_query_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.bufferSizeQueryCount)
			  << " profiling.transpose.call_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.callCount)
			  << " profiling.transpose.time_ms="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.timeMs)
			  << " profiling.transpose.bytes="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.bytes)
			  << " profiling.d2d_copy.copy_count="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.d2dCopy.copyCount)
			  << " profiling.d2d_copy.bytes="
			  << helix::test::benchmark::counterSummary(record.profiling.counters.d2dCopy.bytes)
			  << " integrator_order_count=" << record.problem.integrationOrder
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

std::string evidenceFieldsSummary(const std::vector<helix::test::benchmark::BenchmarkEvidenceField>& fields)
{
	std::ostringstream output;
	for(std::size_t i = 0; i < fields.size(); ++i)
	{
		if(i != 0)
		{
			output << "; ";
		}
		output << fields[i].name << "=" << fields[i].value;
		if(!fields[i].unit.empty())
		{
			output << " " << fields[i].unit;
		}
	}
	return output.str();
}

std::optional<long long> integerCounterValue(const helix::test::benchmark::BenchmarkCounterMetric& metric)
{
	if(metric.integerValue.has_value())
	{
		return *metric.integerValue;
	}
	return std::nullopt;
}

std::string scaledIntegerCounterSummary(const helix::test::benchmark::BenchmarkCounterMetric& metric,
	long long multiplier)
{
	const auto value = integerCounterValue(metric);
	if(!value.has_value())
	{
		return "not_collected";
	}
	return std::to_string(*value * multiplier);
}

std::string legacyWorkspaceAllocSummary(const helix::test::benchmark::BenchmarkSpmmCounters& counters)
{
	const auto callCount = integerCounterValue(counters.callCount);
	if(!callCount.has_value())
	{
		return "not_collected";
	}
	const auto workspaceBytes = integerCounterValue(counters.workspaceBytes);
	if(workspaceBytes.has_value() && *workspaceBytes == 0)
	{
		return "0";
	}
	return std::to_string(*callCount);
}

std::size_t vPathSpmmCallsPerHierarchyBlock()
{
	std::size_t calls = 6;
#ifdef USE_COUNTER
	calls += 2;
#endif
	return calls;
}

std::size_t hDiagonalSpmmCallsAvoided(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return problem.hierarchySize
		* static_cast<std::size_t>(problem.integrationOrder)
		* problem.steadySteps;
}

std::size_t hDiagonalTransposeCallsAvoided(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return 2 * hDiagonalSpmmCallsAvoided(problem);
}

std::size_t hDiagonalSpecializedSpmmCalls(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return problem.hierarchySize
		* vPathSpmmCallsPerHierarchyBlock()
		* static_cast<std::size_t>(problem.integrationOrder)
		* problem.steadySteps;
}

std::size_t hDiagonalSpecializedPhysicalTransposeCalls(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return hDiagonalSpecializedSpmmCalls(problem);
}

std::size_t legacySpinGlassSpinCount(const helix::test::benchmark::BenchmarkProblem& problem)
{
	std::size_t spins = 0;
	std::size_t states = 1;
	while(states < problem.hilbertSize)
	{
		states *= 2;
		++spins;
	}
	return states == problem.hilbertSize ? spins : 0;
}

std::size_t legacySpinGlassStructuredVNonzeros(const helix::test::benchmark::BenchmarkProblem& problem)
{
	const std::size_t spinCount = legacySpinGlassSpinCount(problem);
	return spinCount == 0 ? 0 : problem.hilbertSize * (spinCount + 1);
}

std::size_t complexScalarBytes(const helix::test::benchmark::BenchmarkRecord& record)
{
	return record.caseInfo.precision == "double" ? sizeof(double) * 2 : sizeof(float) * 2;
}

std::size_t fullHierarchyD2DCopyBytes(const helix::test::benchmark::BenchmarkRecord& record)
{
	return record.problem.hierarchySize
		* record.problem.hilbertSize
		* record.problem.hilbertSize
		* complexScalarBytes(record);
}

std::size_t swapIntegratorD2DCopyCount(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return 2 * problem.steadySteps;
}

std::size_t copyBasedIntegratorD2DCopyCount(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return (2 + static_cast<std::size_t>(problem.integrationOrder)) * problem.steadySteps;
}

std::size_t integratorD2DCopyCountAvoided(const helix::test::benchmark::BenchmarkProblem& problem)
{
	return static_cast<std::size_t>(problem.integrationOrder) * problem.steadySteps;
}

std::string integerCounterPlusSummary(
	const helix::test::benchmark::BenchmarkCounterMetric& metric,
	std::size_t increment)
{
	const auto value = integerCounterValue(metric);
	if(!value.has_value())
	{
		return "not_collected";
	}
	return std::to_string(*value + static_cast<long long>(increment));
}

bool measuredSpmmCountersAreReusePath(const helix::test::benchmark::BenchmarkSpmmCounters& counters)
{
	return integerCounterValue(counters.descriptorCreateCount).value_or(-1) == 0
		&& integerCounterValue(counters.bufferSizeQueryCount).value_or(-1) == 0
		&& integerCounterValue(counters.workspaceAllocCount).value_or(-1) == 0;
}

std::string markdownSummary(const helix::test::benchmark::BenchmarkRecord& record,
	const MeasurementResult& mainMeasurement,
	const helix::test::benchmark::BenchmarkArtifactPaths& artifacts)
{
	const std::size_t hSpmmAvoided = hDiagonalSpmmCallsAvoided(record.problem);
	const std::size_t hTransposeAvoided = hDiagonalTransposeCallsAvoided(record.problem);
	const std::size_t expectedSpecializedSpmmCalls = hDiagonalSpecializedSpmmCalls(record.problem);
	const std::size_t expectedPhysicalTransposeCalls =
		hDiagonalSpecializedPhysicalTransposeCalls(record.problem);
	const std::size_t spinCount = legacySpinGlassSpinCount(record.problem);
	const std::size_t structuredVNonzeros = legacySpinGlassStructuredVNonzeros(record.problem);
	const std::size_t fullD2DBytes = fullHierarchyD2DCopyBytes(record);
	const std::size_t expectedSwapD2DCopies = swapIntegratorD2DCopyCount(record.problem);
	const std::size_t previousCopyBasedD2DCopies = copyBasedIntegratorD2DCopyCount(record.problem);
	const std::size_t avoidedD2DCopies = integratorD2DCopyCountAvoided(record.problem);
	const std::size_t expectedSwapD2DBytes = expectedSwapD2DCopies * fullD2DBytes;
	const std::size_t previousCopyBasedD2DBytes = previousCopyBasedD2DCopies * fullD2DBytes;
	const std::size_t avoidedD2DBytes = avoidedD2DCopies * fullD2DBytes;
	const bool attributionMode = record.profiling.timingMode == "attribution";
	const bool reusePath = attributionMode && measuredSpmmCountersAreReusePath(record.profiling.counters.spmm);
	const char* measuredPathName = attributionMode
		? (reusePath ? "Reusable backend plan" : "Legacy wrapper fallback")
		: "Backend attribution disabled";
	const char* measuredPathEvidence = attributionMode
		? (reusePath
			? "Measured `CudaSparseBackendPlan` counters in the profiled steady scope"
			: "Measured fallback wrapper counters in the profiled steady scope")
		: "Pure timing mode disables backend profiling counters for fair wall-clock comparison.";
	const char* measuredPathBehavior = attributionMode
		? (reusePath
			? "Dense pointers are updated with `cusparseDnMatSetValues`; descriptor/workspace setup is zero after warmup for compatible calls."
			: "Fallback path routes through `cuda_types.h` wrappers and reintroduces descriptor and buffer-size setup per SpMM call.")
		: "Counters are reported as `not_collected`; use attribution mode for path-specific evidence.";
	std::ostringstream output;
	output << std::fixed << std::setprecision(3)
		   << "# HELIX benchmark summary\n\n"
		   << "This file is a release/PR handoff summary for benchmark trends. It is not a "
			  "correctness gate, and HELIX does not apply a default speed threshold to this "
			  "benchmark. It does not replace the `examples/outputEnergy.txt` numerical "
			  "baseline.\n\n"
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
		   << "| Timing mode | `" << record.profiling.timingMode << "` |\n"
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
		   << "| Result shape | " << mainMeasurement.reducedDensityShape.count
		   << " x " << mainMeasurement.reducedDensityShape.rows
		   << " x " << mainMeasurement.reducedDensityShape.cols << " |\n\n"
		   << "## Timing (ms)\n\n"
		   << "| Phase | Milliseconds | Notes |\n"
		   << "| --- | ---: | --- |\n"
		   << "| Init | " << record.timing.init << " | Context construction |\n"
		   << "| Warmup | " << record.timing.warmup << " | Warmup propagation |\n"
		   << "| Steady propagation | " << record.timing.steadyPropagation << " | "
		   << record.timing.steadyPropagationScope << " |\n"
		   << "| Result extraction | " << record.timing.resultExtraction << " | Final reduced-density copy |\n"
		   << "| Teardown | " << record.timing.teardown << " | Context destruction |\n\n"
		   << "## Measurement scope\n\n"
		   << "Main timing fields are the benchmark measurement aggregation. Calibration is a separate "
			  "cross-check scope and is never included in main aggregation.\n\n"
		   << "| Field | Value |\n"
		   << "| --- | --- |\n"
		   << "| Main measurement scope | `" << record.measurementScopes.mainMeasurementScope << "` |\n"
		   << "| Main measurement status | `" << record.measurementScopes.mainMeasurementStatus << "` |\n"
		   << "| Calibration scope | `" << record.measurementScopes.calibrationScope << "` |\n"
		   << "| Calibration status | `" << record.measurementScopes.calibrationStatus << "` |\n"
		   << "| Calibration captured | `"
		   << (record.measurementScopes.calibrationCaptured ? "true" : "false") << "` |\n"
		   << "| Calibration excluded from main aggregation | `"
		   << (record.measurementScopes.calibrationExcludedFromMain ? "true" : "false") << "` |\n"
		   << "| NVTX naming convention | `" << record.measurementScopes.nvtxNamingConvention << "` |\n\n"
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
		   << "## Profiling counters\n\n"
		   << "Timing mode: `" << record.profiling.timingMode << "`. "
		   << "`profiling.counters` uses numeric values when collected and `not_collected` for "
			  "reserved fields that were not observed in this run.\n\n"
		   << "| Group | Counter | Value |\n"
		   << "| --- | --- | ---: |\n"
		   << "| spmm | call_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount) << "` |\n"
		   << "| spmm | descriptor_create_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.descriptorCreateCount)
		   << "` |\n"
		   << "| spmm | workspace_alloc_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.workspaceAllocCount)
		   << "` |\n"
		   << "| spmm | workspace_bytes | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.workspaceBytes) << "` |\n"
		   << "| spmm | buffer_size_query_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.bufferSizeQueryCount)
		   << "` |\n"
		   << "| transpose | call_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.callCount) << "` |\n"
		   << "| transpose | time_ms | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.timeMs) << "` |\n"
		   << "| transpose | bytes | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.bytes) << "` |\n"
		   << "| d2d_copy | copy_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.d2dCopy.copyCount) << "` |\n"
		   << "| d2d_copy | bytes | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.d2dCopy.bytes) << "` |\n"
		   << "| sync | device_synchronize_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.sync.deviceSynchronizeCount)
		   << "` |\n"
		   << "| sync | sync_wait_ms | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.sync.syncWaitMs) << "` |\n"
		   << "| result_extraction | sync_wait_ms | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.syncWaitMs)
		   << "` |\n"
		   << "| result_extraction | host_allocation_ms | `"
		   << helix::test::benchmark::counterSummary(
				  record.profiling.counters.resultExtraction.hostAllocationMs)
		   << "` |\n"
		   << "| result_extraction | d2h_copy_ms | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.d2hCopyMs)
		   << "` |\n"
		   << "| result_extraction | conversion_ms | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.conversionMs)
		   << "` |\n"
		   << "| result_extraction | d2h_bytes | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.d2hBytes)
		   << "` |\n"
		   << "| result_extraction | element_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.resultExtraction.elementCount)
		   << "` |\n\n"
		   << "## CUDA 13 cuSPARSE API decision\n\n"
		   << "| API | Decision | Reason | Correctness risk | Workspace lifetime risk | Graph capture impact |\n"
		   << "| --- | --- | --- | --- | --- | --- |\n"
		   << "| `cusparseDnMatSetValues` | adopt | Dense input/output pointers change between hierarchy blocks while shape stays fixed; the backend plan updates only those pointers before `cusparseSpMM`. | Low if shape/leading dimensions are unchanged; CUDA micro tests cover pointer update with different buffers. | No workspace ownership change; existing workspace remains plan-owned. | Positive precondition for future capture because descriptors stay stable, but graph capture is not implemented in T4. |\n"
		   << "| `cusparseSpMatSetValues` | reject for T4 | Current H/V sparse values are stable and use separate reusable plans; values-only rebinding is unnecessary. | Avoids silently rebinding the wrong sparse operator into a cached plan. | No additional workspace lifetime state. | Neutral; revisit only for a future values-only mutable sparse operator. |\n"
		   << "| `cusparseCsrSetPointers` | defer | Full CSR pointer rebinding would need topology/nnz lifetime rules beyond the current stable H/V descriptors. | Medium; row/column/value pointer mismatches can corrupt the sparse operator if reused incorrectly. | Could invalidate preprocess/workspace assumptions if topology changes. | Potentially useful for future dynamic CSR or layout work, not required for this reuse proof. |\n"
		   << "| `cusparseSpMM_bufferSize` | adopt | Query once when a plan is created; reuse the resulting workspace for compatible calls. | Low; incompatible shapes are rejected by the plan. | Workspace is plan-owned and released by `destroy()` / `clearLiouvilleStorage()`. | Stable workspace ownership is a prerequisite for graph capture, but capture validation is deferred. |\n"
		   << "| `cusparseSpMM_preprocess` | defer | CUDA 13 preprocess may help selected algorithms, but active-buffer and pointer-stability constraints need separate numerical and capture gates. | Medium until algorithm-specific determinism and pointer update behavior are tested. | Medium; preprocess can add state tied to the active external buffer. | Potentially positive for graph capture, but T4 does not claim capture readiness. |\n\n"
		   << "## Structural SpMM reuse comparison\n\n"
		   << "The legacy wrapper row is a static before estimate from `src/cuda_types.h` for the same "
			  "observed steady-scope SpMM call count. The reuse row is measured from "
			  "`profiling.counters.spmm` after warmup has primed the backend plan.\n\n"
		   << "| Path | Evidence | SpMM calls | Descriptor creates | Buffer-size queries | Workspace allocations | Per-SpMM setup behavior |\n"
		   << "| --- | --- | ---: | ---: | ---: | ---: | --- |\n"
		   << "| Legacy wrapper compatibility path | Static wrapper structure: `cusparseCreateCsr` + two `cusparseCreateDnMat` + `cusparseSpMM_bufferSize` per wrapper call | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount)
		   << "` | `"
		   << scaledIntegerCounterSummary(record.profiling.counters.spmm.callCount, 3)
		   << "` | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount)
		   << "` | `"
		   << legacyWorkspaceAllocSummary(record.profiling.counters.spmm)
		   << "` | Rebuilds descriptors and queries workspace per SpMM call. |\n"
		   << "| " << measuredPathName << " | " << measuredPathEvidence << " | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount)
		   << "` | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.descriptorCreateCount)
		   << "` | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.bufferSizeQueryCount)
		   << "` | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.workspaceAllocCount)
		   << "` | " << measuredPathBehavior << " |\n\n"
		   << "## H_DIAGONAL elementwise specialization comparison\n\n"
		   << "The compiled `H_DIAGONAL` path now evaluates `-i * (H[row] - H[column]) * rho[row,column]` "
			  "with one elementwise CUDA kernel per hierarchy block/RHS evaluation. This removes "
			  "the previous H-path DGMM, H-path SpMM, and two H-path physical transposes while "
			  "leaving the generic non-diagonal sparse commutator fallback unchanged.\n\n"
		   << "| Path | Evidence | Steady SpMM calls | H SpMM calls avoided | H transpose calls avoided |\n"
		   << "| --- | --- | ---: | ---: | ---: |\n"
		   << "| Previous compiled diagonal-H sparse path | Structural estimate: measured specialized SpMM calls plus one H SpMM per hierarchy block per integration substep | `"
		   << integerCounterPlusSummary(record.profiling.counters.spmm.callCount, hSpmmAvoided)
		   << "` | `0` | `0` |\n"
		   << "| Elementwise H_DIAGONAL path | Measured `profiling.counters.spmm.call_count`; expected V-path-only calls `"
		   << expectedSpecializedSpmmCalls << "` | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount)
		   << "` | `" << hSpmmAvoided << "` | `" << hTransposeAvoided << "` |\n\n"
		   << "## Structured V specialization spike decision\n\n"
		   << "Decision: `defer_legacy_spin_glass_only`. The default legacy spin-glass `V` operator "
			  "has a known diagonal plus single-spin-flip structure, but replacing the current "
			  "generic sparse SpMM path with a model-specific kernel is deferred to a separate "
			  "spike with its own reference and baseline gates.\n\n"
		   << "| Field | Value |\n"
		   << "| --- | --- |\n"
		   << "| Decision | `defer_legacy_spin_glass_only` |\n"
		   << "| Candidate scope | private default legacy spin-glass adapter only |\n"
		   << "| Generic sparse contract | `System::from_sparse()` remains validation-only and unaffected |\n"
		   << "| Public API expansion | rejected for v0.0.4 |\n"
		   << "| Speed threshold | none; benchmark evidence is trend evidence only |\n"
		   << "| Spin count inferred from N | `" << spinCount << "` |\n"
		   << "| Structured V nnz estimate | `" << structuredVNonzeros << "` |\n"
		   << "| Current V-path SpMM calls in steady scope | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.spmm.callCount)
		   << "` |\n"
		   << "| Current V-path physical transpose calls in steady scope | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.callCount)
		   << "` |\n\n"
		   << "Boundary: this decision does not promote arbitrary sparse HEOM runtime support. "
			  "If structured V is revisited, it should live behind the existing private legacy "
			  "spin-glass compatibility adapter, keep the reusable sparse plan as the generic "
			  "fallback, and prove equivalence with CUDA reference-kernel tests plus quick and "
			  "`HELIX_STEPS=1980` baselines.\n\n"
		   << "## Integrator D2D recurrence comparison\n\n"
		   << "The Taylor-like recurrence now keeps the accumulated result in a private scratch "
			  "buffer and alternates the current recurrence state between `dRho` and the derivative "
			  "scratch buffer. This removes the previous full-buffer `B -> dRho` copy after each "
			  "integration order. Final ownership is unchanged: before `develop()` returns, the "
			  "accumulator is copied back into global `dRho`, and result extraction reads block 0 "
			  "from `dRho`.\n\n"
		   << "| Metric | Value |\n"
		   << "| --- | ---: |\n"
		   << "| integrator_order_count | `" << record.problem.integrationOrder << "` |\n"
		   << "| steady_steps_profiled | `" << record.problem.steadySteps << "` |\n"
		   << "| full_hierarchy_copy_bytes | `" << fullD2DBytes << "` |\n"
		   << "| previous_copy_based_copy_count | `" << previousCopyBasedD2DCopies << "` |\n"
		   << "| previous_copy_based_copy_bytes | `" << previousCopyBasedD2DBytes << "` |\n"
		   << "| swap_recurrence_expected_copy_count | `" << expectedSwapD2DCopies << "` |\n"
		   << "| swap_recurrence_expected_copy_bytes | `" << expectedSwapD2DBytes << "` |\n"
		   << "| avoided_copy_count | `" << avoidedD2DCopies << "` |\n"
		   << "| avoided_copy_bytes | `" << avoidedD2DBytes << "` |\n"
		   << "| measured_d2d_copy_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.d2dCopy.copyCount)
		   << "` |\n"
		   << "| measured_d2d_copy_bytes | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.d2dCopy.bytes)
		   << "` |\n\n"
		   << "## Layout / transpose option matrix\n\n"
		   << "Current benchmark evidence records physical transpose call count and bytes in "
			  "`profiling.counters.transpose`. `transpose.time_ms` intentionally remains "
			  "`not_collected`: adding event timing inside the production wrapper would introduce "
			  "stream synchronization pressure into the path being measured. Use Nsight or a "
			  "separate event-timing experiment when wall-clock attribution is needed.\n\n"
		   << "| Metric | Value |\n"
		   << "| --- | ---: |\n"
		   << "| transpose_call_count | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.callCount)
		   << "` |\n"
		   << "| expected_current_physical_transpose_call_count | `"
		   << expectedPhysicalTransposeCalls << "` |\n"
		   << "| transpose_bytes | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.bytes)
		   << "` |\n"
		   << "| transpose_time_ms | `"
		   << helix::test::benchmark::counterSummary(record.profiling.counters.transpose.timeMs)
		   << "` |\n"
		   << "| transpose_time_ms_policy | `not_collected_without_extra_stream_sync` |\n\n"
		   << "| Option | Decision | Reason | Compatibility boundary |\n"
		   << "| --- | --- | --- | --- |\n"
		   << "| Current physical transpose around sparse commutator outputs | adopt for v0.0.4 | It preserves the tested row-major density buffer semantics while exposing the remaining cost through counters. | Keep `transpose()` shape-safe and profiled; revisit only with small reference and baseline gates. |\n"
		   << "| cuSPARSE dense descriptor order/opB rewrite | defer | The current reusable plan uses stable column-major descriptors plus explicit transposes; changing order/opB would couple cuSPARSE assumptions to cuBLAS accumulation and needs a dedicated reference gate. | Prototype behind a local option before replacing the production path. |\n"
		   << "| Internal row-major density storage | adopt/retain | `dRho`, result extraction, public shape tests, and energy helpers already agree on row-major flat indexing. | Any future backend-local layout must convert at the result extraction boundary. |\n"
		   << "| Public result order | adopt/lock | public result order remains row-major via `ReducedDensityShape::storageOrder`. | `ResultExtractor::final_reduced_density()` is the public conversion boundary. |\n"
		   << "| Full public layout abstraction | reject for v0.0.4 | T7 only needs a backend decision and compatibility statement, not a public API expansion. | Reconsider only when multiple public storage orders are actually supported and tested. |\n\n"
		   << "## Synchronization audit and replacement plan\n\n"
		   << "T8 does not remove production synchronizations. Each site below keeps an explicit "
			  "correctness and error boundary until the listed stream/event dependency is "
			  "implemented and tested.\n\n"
		   << "| Site | Current synchronization | Retain or replacement reason | Event/stream dependency plan | Error/debug boundary |\n"
		   << "| --- | --- | --- | --- | --- |\n"
		   << "| `measureCudaPhase()` | `cudaDeviceSynchronize()` before and after each measured phase (`init`, `warmup`, `steady_propagation`, `result_extraction`, `teardown`; 10 runner fences per benchmark record). | Retain in benchmark timing path so wall-clock phases are closed intervals and memory snapshots have a complete device boundary. | Use CUDA events only in a future profiling mode that does not need whole-device timing fences; keep default runner fences for release artifacts. | Benchmark runner throws immediately on CUDA errors at phase boundaries. |\n"
		   << "| `LegacyRuntimeSession::run_steps()` | `cudaDeviceSynchronize()` after every `develop()` call. | Retain as the public `Context::run_steps()` completion and error boundary while legacy global state has no explicit stream owner. | Replace only after runtime session owns an integration stream/event and callers have an explicit completion contract. | Debug/profile mode should keep this fence or an equivalent terminal stream synchronize. |\n"
		   << "| `develop()` | Device-wide fence after `getdRhoSparse()`, `cublasScal`, and `cublasAxpy` in each integration order. | Required today because per-hierarchy sparse streams produce the derivative while the global cuBLAS handle consumes it and later iterations may read swapped buffers. | Record completion events for sparse streams, wait on the integration/cuBLAS stream before scale/accumulate, then make sparse streams wait on the integration event before the next order. | Check CUDA status after each event wait and keep a debug sync mode for first-failure attribution. |\n"
		   << "| `getdRhoSparse()` stage barrier | Device-wide fence between the L/V sparse commutator stage and hierarchy-coupling stage. | Phase 2 reads `buffer` and `pdRho` entries produced by other hierarchy streams; per-stream ordering alone is insufficient. | Record one event per hierarchy stream after stage 1; stage 2 waits on the producer events for each referenced hierarchy block (or a tested fan-in barrier). | Preserve a stage boundary error check before launching dependent BLAS/SpMM work. |\n"
		   << "| `getdRhoSparse()` exit barrier | Device-wide fence after all hierarchy-coupling work. | Caller `develop()` immediately consumes `drhoVec` from a different cuBLAS stream/handle. | Record per-stream completion events and wait on the integration/cuBLAS stream before `cublasScal`/`cublasAxpy`. | Keep an explicit post-derivative error boundary in debug/profile sync mode. |\n"
		   << "| `clearLiouvilleStorage()` | Device-wide fence at entry plus per-stream synchronizes before destroying streams/handles/descriptors. | Resource teardown must not race queued kernels, cuBLAS work, cuSPARSE descriptors, or plan-owned workspaces. | Prefer per-stream synchronize/event joins for owned streams; retain a device fence while legacy global state can queue work outside tracked streams. | Teardown remains a hard synchronization boundary. |\n\n"
		   << "## CUDA Graph feasibility decision\n\n"
		   << "Decision: `defer_fixed_shape_capture` for v0.0.4. Fixed-shape capture is promising "
			  "because the default profile has stable dimensions and warmed reusable SpMM plans, "
			  "but it should not enter production until the synchronization replacement plan above "
			  "has a correctness gate.\n\n"
		   << "| Constraint | Current evidence | Capture impact | Decision |\n"
		   << "| --- | --- | --- | --- |\n"
		   << "| Shape stability | N=`" << record.problem.hilbertSize << "`, hierarchy=`"
		   << record.problem.hierarchySize << "`, integration_order=`"
		   << record.problem.integrationOrder << "`, steady_steps=`" << record.problem.steadySteps
		   << "` in this benchmark record. | Positive for fixed-shape one-step capture after warmup. | Adopt assumption for a spike only. |\n"
		   << "| Workspace lifetime | `CudaSparseBackendPlan` owns descriptors/workspace and steady counters show descriptor creates, workspace allocations, and buffer-size queries are zero after warmup. | Positive precondition; capture must start after initialization and plan warmup. | Adopt pre-capture warmup requirement. |\n"
		   << "| Pointer stability | `dRho`, scratch `F`/`B`, sparse buffers, and descriptor dense pointers are stable within the fixed compiled profile; `cusparseDnMatSetValues` updates values pointers before SpMM. | Promising, but captured graphs bake pointer values and update ordering. | Defer until pointer-role swap is covered by a graph replay test. |\n"
		   << "| Preprocess / allocation APIs | `cusparseSpMM_bufferSize` is outside steady scope; `cusparseSpMM_preprocess` remains deferred. | Capture must exclude allocation, descriptor creation, and unvalidated preprocess calls. | Defer preprocess inside capture. |\n"
		   << "| Synchronization APIs | `develop()`, `getdRhoSparse()`, `LegacyRuntimeSession::run_steps()`, and teardown still use device-wide fences. | Device synchronization is capture-hostile and hides real stream dependencies. | Blocker; implement event dependencies first. |\n"
		   << "| Result extraction | `ResultExtractor` intentionally synchronizes before D2H copy and conversion; public order remains row-major. | Keep extraction outside propagation capture. | Capture propagation only. |\n"
		   << "| Debug/profile mode | Current evidence relies on runner phase fences and internal sync counters. | Debug mode needs explicit error boundaries even if production replay becomes async. | Require a debug sync mode for any future graph path. |\n\n"
		   << "Rollback switch: set `HELIX_CUSPARSE_REUSE_PLAN=0` to route sparse calls through the "
			  "`cuda_types.h` compatibility wrappers. This is a correctness triage fallback and "
			  "reintroduces per-call wrapper setup, so it is not a performance evidence path.\n\n"
		   << "## Profiling evidence\n\n"
		   << "- Instrumentation: `" << joinStrings(record.profiling.instrumentation) << "`\n"
		   << "- NVTX enabled: `" << (record.profiling.nvtxEnabled ? "true" : "false") << "`\n"
		   << "- Nsight artifact (`profiling.nsight_artifact`): `"
		   << helix::test::benchmark::nsightArtifactSummaryValue(record.profiling.nsightArtifact) << "`\n"
		   << "- Nsight directory: `" << artifacts.nsightDir.string() << "`\n\n"
		   << "| Hypothesis | Status | Fields | Method | Interpretation | Downstream action |\n"
		   << "| --- | --- | --- | --- | --- | --- |\n";
	for(const auto& hypothesis : record.profiling.hypotheses)
	{
		output << "| " << hypothesis.id << " " << hypothesis.name
			   << " | `" << hypothesis.status << "`"
			   << " | " << evidenceFieldsSummary(hypothesis.fields)
			   << " | " << hypothesis.method
			   << " | " << hypothesis.interpretation
			   << " | " << hypothesis.downstreamAction << " |\n";
	}
	output << "\n";
	output
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
		   << "- Measurement scope: main=`" << record.measurementScopes.mainMeasurementScope
		   << "`, calibration=`" << record.measurementScopes.calibrationScope
		   << "`, calibration_captured=`"
		   << (record.measurementScopes.calibrationCaptured ? "true" : "false")
		   << "`, calibration_excluded_from_main=`"
		   << (record.measurementScopes.calibrationExcludedFromMain ? "true" : "false") << "`.\n"
		   << "- Memory: peak_device_bytes=" << record.memory.peakDeviceBytes
		   << ", device_delta_bytes=" << record.memory.deviceDeltaBytes
		   << ", method=`" << record.memory.measurementMethod << "`.\n"
		   << "- Timing mode: `" << record.profiling.timingMode << "`.\n"
		   << "- Gates: correctness=`" << record.gates.correctnessGateStatus << "`, baseline=`"
		   << record.gates.baselineGateStatus << "`; speed threshold=`none`.\n"
		   << "- Profiling evidence: H-001..H-005 slots are populated in `profiling.hypotheses`; "
			  "`not_collected` marks intentionally deferred counters. CUDA 13 API decisions, "
			  "the structural legacy-vs-reuse comparison, the structured V specialization "
			  "defer decision, the integrator D2D before-after comparison, the layout/transpose "
			  "option matrix, the synchronization audit, and the CUDA Graph feasibility decision "
			  "are recorded in this summary.\n";
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
	const MeasurementResult& mainMeasurement)
{
	helix::test::benchmark::ensureArtifactDirectories(artifacts);
	writeTextFile(artifacts.jsonl,
		helix::test::benchmark::toJsonLine(record),
		std::ios::out | std::ios::app);
	writeTextFile(artifacts.summary,
		markdownSummary(record, mainMeasurement, artifacts),
		std::ios::out | std::ios::trunc);
}

std::string readTextFile(const std::filesystem::path& path)
{
	std::ifstream input(path);
	if(!input)
	{
		throw std::runtime_error("failed to open benchmark artifact for review: " + path.string());
	}
	std::ostringstream contents;
	contents << input.rdbuf();
	return contents.str();
}

void requireFileContains(const std::filesystem::path& path, const std::string& needle, const std::string& message)
{
	const std::string contents = readTextFile(path);
	require(contents.find(needle) != std::string::npos, message + ": missing " + needle);
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
		const std::size_t warmupSteps =
			positiveSizeEnvOrDefault("HELIX_BENCHMARK_WARMUP_STEPS", kDefaultWarmupSteps);
		const std::size_t steadySteps =
			positiveSizeEnvOrDefault("HELIX_BENCHMARK_STEADY_STEPS", kDefaultSteadySteps);
		const std::size_t totalSteps = warmupSteps + steadySteps;
		const bool collectBackendProfiling =
			envBoolOrDefault("HELIX_BENCHMARK_COLLECT_BACKEND_PROFILING", true);
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
		helix::library::BackendProfilingCounters backendProfilingCounters;
		helix::test::benchmark::BenchmarkTiming timing;
		const bool captureCalibration = envBoolOrDefault("HELIX_BENCHMARK_CAPTURE_CALIBRATION", true);

		timing.init = measureCudaPhase(memoryTracker, [&]() {
			context = std::make_unique<helix::Context>(options);
		});
		timing.warmup = measureCudaPhase(memoryTracker, [&]() {
			context->run_steps(warmupSteps);
		});
		if(collectBackendProfiling)
		{
			helix::library::ScopedBackendProfiling profiling;
			timing.steadyPropagation = measureCudaPhase(memoryTracker, [&]() {
				context->run_steps(steadySteps);
			});
			timing.resultExtraction = measureCudaPhase(memoryTracker, [&]() {
				directDensity = context->reduced_density();
			});
			backendProfilingCounters = profiling.snapshot();
		}
		else
		{
			timing.steadyPropagation = measureCudaPhase(memoryTracker, [&]() {
				context->run_steps(steadySteps);
			});
			timing.resultExtraction = measureCudaPhase(memoryTracker, [&]() {
				directDensity = context->reduced_density();
			});
		}
		const MeasurementResult mainMeasurement = makeMainMeasurementResult(options, hierarchy, directDensity, totalSteps);
		timing.teardown = measureCudaPhase(memoryTracker, [&]() {
			context->destroy();
			context.reset();
		});

		if(captureCalibration)
		{
			const helix::RunResult calibration = runSolverCalibration(options, totalSteps);
			validateCalibration(directDensity, calibration, totalSteps);
		}

		const auto legacyOutputs = helix::test::benchmark::findLegacyOutputs(workspace.path());
		require(legacyOutputs.empty(), "benchmark runner must not write legacy CLI output files");

		helix::test::benchmark::BenchmarkMemory memory;
		memory.peakDeviceBytes = memoryTracker.peakDeviceBytes();
		memory.deviceDeltaBytes = memoryTracker.deviceDeltaBytes();
		memory.measurementMethod = "cudaMemGetInfo_delta";

		const auto profilingCounters = benchmarkCountersFromSnapshot(backendProfilingCounters);
		const auto record = makeRecord(timestamp,
			deviceProperties,
			driverVersion,
			runtimeVersion,
			bath,
			hierarchy,
			mainMeasurement,
			warmupSteps,
			steadySteps,
			captureCalibration,
			timing,
			memory,
			profilingCounters,
			collectBackendProfiling,
			optionalEnv("HELIX_BENCHMARK_NSIGHT_ARTIFACT"));
		if(collectBackendProfiling)
		{
			const auto measuredSteadySpmmCalls = integerCounterValue(record.profiling.counters.spmm.callCount);
			require(measuredSteadySpmmCalls.has_value(), "benchmark must collect steady SpMM call count");
			require(*measuredSteadySpmmCalls == static_cast<long long>(hDiagonalSpecializedSpmmCalls(record.problem)),
				"benchmark steady SpMM call count must reflect H_DIAGONAL elementwise specialization");
			const auto measuredTransposeCount = integerCounterValue(record.profiling.counters.transpose.callCount);
			require(measuredTransposeCount.has_value(), "benchmark must collect physical transpose call count");
			require(*measuredTransposeCount
					== static_cast<long long>(hDiagonalSpecializedPhysicalTransposeCalls(record.problem)),
				"benchmark transpose call count must reflect current physical transpose strategy");
			const auto measuredTransposeBytes = integerCounterValue(record.profiling.counters.transpose.bytes);
			require(measuredTransposeBytes.has_value(), "benchmark must collect physical transpose bytes");
			require(*measuredTransposeBytes == static_cast<long long>(
				hDiagonalSpecializedPhysicalTransposeCalls(record.problem)
				* record.problem.hilbertSize
				* record.problem.hilbertSize
				* complexScalarBytes(record)),
				"benchmark transpose bytes must reflect current physical transpose strategy");
			const auto measuredD2DCopyCount = integerCounterValue(record.profiling.counters.d2dCopy.copyCount);
			require(measuredD2DCopyCount.has_value(), "benchmark must collect integrator D2D copy count");
			require(*measuredD2DCopyCount == static_cast<long long>(swapIntegratorD2DCopyCount(record.problem)),
				"benchmark D2D copy count must reflect swap recurrence initial/final copies only");
			const auto measuredD2DBytes = integerCounterValue(record.profiling.counters.d2dCopy.bytes);
			require(measuredD2DBytes.has_value(), "benchmark must collect integrator D2D copy bytes");
			require(*measuredD2DBytes == static_cast<long long>(
				swapIntegratorD2DCopyCount(record.problem) * fullHierarchyD2DCopyBytes(record)),
				"benchmark D2D bytes must reflect two full hierarchy copies per steady develop");
		}
		validateRecord(record);
		writeArtifacts(artifacts, record, mainMeasurement);

		const auto misplacedArtifacts =
			helix::test::benchmark::findMisplacedBenchmarkArtifacts(workspace.path(), artifacts.root);
		require(misplacedArtifacts.empty(), "benchmark JSONL/summary must only be written under artifact root");
		require(std::filesystem::exists(artifacts.jsonl), "benchmark JSONL artifact must exist");
		require(std::filesystem::exists(artifacts.summary), "benchmark summary artifact must exist");
		require(std::filesystem::is_directory(artifacts.nsightDir), "benchmark nsight artifact directory must exist");
		requireFileContains(artifacts.jsonl, "\"measurement_scope\":{", "benchmark JSONL records scope state");
		requireFileContains(artifacts.jsonl,
			"\"calibration_excluded_from_main\":true",
			"benchmark JSONL records calibration exclusion");
		requireFileContains(artifacts.jsonl,
			std::string("\"timing_mode\":\"") + timingModeName(collectBackendProfiling) + "\"",
			"benchmark JSONL records timing mode");
		requireFileContains(artifacts.jsonl, "\"counters\":{", "benchmark JSONL records profiling counters");
		if(collectBackendProfiling)
		{
			requireFileContains(artifacts.jsonl, "\"spmm\":{\"call_count\":",
				"benchmark JSONL records SpMM call count");
			requireFileContains(artifacts.jsonl, "\"d2d_copy\":{\"copy_count\":",
				"benchmark JSONL records D2D copy count");
			requireFileContains(artifacts.jsonl, "\"transpose\":{\"call_count\":",
				"benchmark JSONL records transpose call count");
			requireFileContains(artifacts.jsonl,
				"\"structured_v_specialization_decision\"",
				"benchmark JSONL records structured V specialization decision");
			if(cusparseReusePlanEnabledFromEnv())
			{
				requireFileContains(artifacts.jsonl, "\"descriptor_create_count\":0",
					"benchmark JSONL records zero steady descriptor creates after warmup");
				requireFileContains(artifacts.jsonl, "\"workspace_alloc_count\":0",
					"benchmark JSONL records zero steady workspace allocations after warmup");
				requireFileContains(artifacts.jsonl, "\"buffer_size_query_count\":0",
					"benchmark JSONL records zero steady buffer-size queries after warmup");
			}
		}
		else
		{
			requireFileContains(artifacts.jsonl, "\"spmm\":{\"call_count\":\"not_collected\"",
				"pure timing JSONL records SpMM counters as not_collected");
		}
		requireFileContains(artifacts.jsonl,
			"\"result_extraction\":{",
			"benchmark JSONL records result extraction counters");
		requireFileContains(artifacts.jsonl, "\"d2h_bytes\":", "benchmark JSONL records D2H bytes");
		requireFileContains(artifacts.summary, "## Measurement scope", "benchmark summary records scope state");
		requireFileContains(artifacts.summary,
			"Calibration excluded from main aggregation",
			"benchmark summary records calibration exclusion");
		requireFileContains(artifacts.summary, "## Profiling counters", "benchmark summary records counter table");
		requireFileContains(artifacts.summary,
			"host_allocation_ms",
			"benchmark summary records result extraction host allocation timing");
		requireFileContains(artifacts.summary,
			"## CUDA 13 cuSPARSE API decision",
			"benchmark summary records the CUDA 13 API decision table");
		requireFileContains(artifacts.summary,
			"cusparseDnMatSetValues",
			"benchmark summary records adopted dense pointer update API");
		requireFileContains(artifacts.summary,
			"## Structural SpMM reuse comparison",
			"benchmark summary records structural reuse comparison");
		requireFileContains(artifacts.summary,
			"## H_DIAGONAL elementwise specialization comparison",
			"benchmark summary records diagonal H specialization comparison");
		requireFileContains(artifacts.summary,
			"## Structured V specialization spike decision",
			"benchmark summary records structured V specialization decision");
		requireFileContains(artifacts.summary,
			"remains validation-only and unaffected",
			"benchmark summary records generic sparse contract boundary");
		requireFileContains(artifacts.summary,
			"## Integrator D2D recurrence comparison",
			"benchmark summary records integrator D2D before-after comparison");
		requireFileContains(artifacts.summary,
			"## Layout / transpose option matrix",
			"benchmark summary records layout transpose decision matrix");
		requireFileContains(artifacts.summary,
			"transpose_time_ms_policy",
			"benchmark summary records transpose timing fallback policy");
		requireFileContains(artifacts.summary,
			"public result order remains row-major",
			"benchmark summary records public result order compatibility statement");
		requireFileContains(artifacts.summary,
			"## Synchronization audit and replacement plan",
			"benchmark summary records synchronization audit");
		requireFileContains(artifacts.summary,
			"measureCudaPhase",
			"benchmark summary records runner synchronization site");
		requireFileContains(artifacts.summary,
			"## CUDA Graph feasibility decision",
			"benchmark summary records CUDA Graph feasibility decision");
		requireFileContains(artifacts.summary,
			"defer_fixed_shape_capture",
			"benchmark summary records fixed-shape graph decision");
		requireFileContains(artifacts.summary,
			"Final ownership is unchanged",
			"benchmark summary records final dRho ownership statement");
		requireFileContains(artifacts.summary,
			"HELIX_CUSPARSE_REUSE_PLAN=0",
			"benchmark summary records the fallback switch");

		std::cout << helix::test::benchmark::toJsonLine(record);
		printSummary(record, mainMeasurement);
		return 0;
	}
	catch(const std::exception& error)
	{
		std::cerr << "legacy_spin_glass_benchmark failed: " << error.what() << '\n';
		return 1;
	}
}
