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
	bool calibrationCaptured,
	const helix::test::benchmark::BenchmarkTiming& timing,
	const helix::test::benchmark::BenchmarkMemory& memory,
	const helix::test::benchmark::BenchmarkProfilingCounters& profilingCounters,
	const std::optional<std::string>& nsightArtifact)
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
	record.caseInfo.backend = toString(mainMeasurement.diagnostics.backend);
	record.caseInfo.precision = toString(mainMeasurement.diagnostics.precision);
	record.caseInfo.resultMode = toString(helix::ResultMode::FinalState);
	record.problem.hilbertSize = mainMeasurement.diagnostics.hilbertSize;
	record.problem.kMax = bath.padeTerms;
	record.problem.jMax = hierarchy.maxDepth;
	record.problem.hierarchySize = mainMeasurement.diagnostics.hierarchySize;
	record.problem.timeStep = mainMeasurement.diagnostics.timeStep;
	record.problem.integrationOrder = mainMeasurement.diagnostics.integrationOrder;
	record.problem.steps = kWarmupSteps + kSteadySteps;
	record.problem.warmupSteps = kWarmupSteps;
	record.problem.steadySteps = kSteadySteps;
	record.timing = timing;
	record.measurementScopes.calibrationCaptured = calibrationCaptured;
	record.measurementScopes.calibrationStatus = calibrationCaptured ? "captured" : "not_captured";
	record.measurementScopes.calibrationExcludedFromMain = true;
	record.memory = memory;
	record.diagnostics = mirrorDiagnostics(mainMeasurement.diagnostics);
	record.gates.correctnessGateStatus = envOrDefault("HELIX_BENCHMARK_CORRECTNESS_GATE_STATUS", "not_run");
	record.gates.baselineGateStatus = envOrDefault("HELIX_BENCHMARK_BASELINE_GATE_STATUS", "not_run");
	record.profiling.instrumentation = {"runner_wall_clock", "cudaDeviceSynchronize_phase_boundaries"};
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
		? "Context phase timing with HEOMSolver smoke calibration; calibration excluded from main aggregation; no legacy CLI output files expected"
		: "Context phase timing without HEOMSolver smoke calibration; main-only artifact; no legacy CLI output files expected";
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
	const std::size_t fullD2DBytes = fullHierarchyD2DCopyBytes(record);
	const std::size_t expectedSwapD2DCopies = swapIntegratorD2DCopyCount(record.problem);
	const std::size_t previousCopyBasedD2DCopies = copyBasedIntegratorD2DCopyCount(record.problem);
	const std::size_t avoidedD2DCopies = integratorD2DCopyCountAvoided(record.problem);
	const std::size_t expectedSwapD2DBytes = expectedSwapD2DCopies * fullD2DBytes;
	const std::size_t previousCopyBasedD2DBytes = previousCopyBasedD2DCopies * fullD2DBytes;
	const std::size_t avoidedD2DBytes = avoidedD2DCopies * fullD2DBytes;
	const bool reusePath = measuredSpmmCountersAreReusePath(record.profiling.counters.spmm);
	const char* measuredPathName = reusePath ? "Reusable backend plan" : "Legacy wrapper fallback";
	const char* measuredPathEvidence = reusePath
		? "Measured `CudaSparseBackendPlan` counters in the profiled steady scope"
		: "Measured fallback wrapper counters in the profiled steady scope";
	const char* measuredPathBehavior = reusePath
		? "Dense pointers are updated with `cusparseDnMatSetValues`; descriptor/workspace setup is zero after warmup for compatible calls."
		: "Fallback path routes through `cuda_types.h` wrappers and reintroduces descriptor and buffer-size setup per SpMM call.";
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
		   << "- Gates: correctness=`" << record.gates.correctnessGateStatus << "`, baseline=`"
		   << record.gates.baselineGateStatus << "`; speed threshold=`none`.\n"
		   << "- Profiling evidence: H-001..H-005 slots are populated in `profiling.hypotheses`; "
			  "`not_collected` marks intentionally deferred counters. CUDA 13 API decisions, "
			  "the structural legacy-vs-reuse comparison, and the integrator D2D before-after "
			  "comparison are recorded in this summary.\n";
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
		helix::library::BackendProfilingCounters backendProfilingCounters;
		helix::test::benchmark::BenchmarkTiming timing;
		const bool captureCalibration = envBoolOrDefault("HELIX_BENCHMARK_CAPTURE_CALIBRATION", true);

		timing.init = measureCudaPhase(memoryTracker, [&]() {
			context = std::make_unique<helix::Context>(options);
		});
		timing.warmup = measureCudaPhase(memoryTracker, [&]() {
			context->run_steps(kWarmupSteps);
		});
		{
			helix::library::ScopedBackendProfiling profiling;
			timing.steadyPropagation = measureCudaPhase(memoryTracker, [&]() {
				context->run_steps(kSteadySteps);
			});
			timing.resultExtraction = measureCudaPhase(memoryTracker, [&]() {
				directDensity = context->reduced_density();
			});
			backendProfilingCounters = profiling.snapshot();
		}
		const MeasurementResult mainMeasurement = makeMainMeasurementResult(options, hierarchy, directDensity, totalSteps);
		timing.teardown = measureCudaPhase(memoryTracker, [&]() {
			context->destroy();
			context.reset();
		});

		if(captureCalibration)
		{
			const helix::RunResult calibration = runSolverCalibration(options, totalSteps);
			validateCalibration(directDensity, calibration);
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
			captureCalibration,
			timing,
			memory,
			profilingCounters,
			optionalEnv("HELIX_BENCHMARK_NSIGHT_ARTIFACT"));
		const auto measuredSteadySpmmCalls = integerCounterValue(record.profiling.counters.spmm.callCount);
		require(measuredSteadySpmmCalls.has_value(), "benchmark must collect steady SpMM call count");
		require(*measuredSteadySpmmCalls == static_cast<long long>(hDiagonalSpecializedSpmmCalls(record.problem)),
			"benchmark steady SpMM call count must reflect H_DIAGONAL elementwise specialization");
		const auto measuredD2DCopyCount = integerCounterValue(record.profiling.counters.d2dCopy.copyCount);
		require(measuredD2DCopyCount.has_value(), "benchmark must collect integrator D2D copy count");
		require(*measuredD2DCopyCount == static_cast<long long>(swapIntegratorD2DCopyCount(record.problem)),
			"benchmark D2D copy count must reflect swap recurrence initial/final copies only");
		const auto measuredD2DBytes = integerCounterValue(record.profiling.counters.d2dCopy.bytes);
		require(measuredD2DBytes.has_value(), "benchmark must collect integrator D2D copy bytes");
		require(*measuredD2DBytes == static_cast<long long>(
			swapIntegratorD2DCopyCount(record.problem) * fullHierarchyD2DCopyBytes(record)),
			"benchmark D2D bytes must reflect two full hierarchy copies per steady develop");
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
		requireFileContains(artifacts.jsonl, "\"counters\":{", "benchmark JSONL records profiling counters");
		requireFileContains(artifacts.jsonl, "\"spmm\":{\"call_count\":",
			"benchmark JSONL records SpMM call count");
		requireFileContains(artifacts.jsonl, "\"d2d_copy\":{\"copy_count\":",
			"benchmark JSONL records D2D copy count");
		if(cusparseReusePlanEnabledFromEnv())
		{
			requireFileContains(artifacts.jsonl, "\"descriptor_create_count\":0",
				"benchmark JSONL records zero steady descriptor creates after warmup");
			requireFileContains(artifacts.jsonl, "\"workspace_alloc_count\":0",
				"benchmark JSONL records zero steady workspace allocations after warmup");
			requireFileContains(artifacts.jsonl, "\"buffer_size_query_count\":0",
				"benchmark JSONL records zero steady buffer-size queries after warmup");
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
			"## Integrator D2D recurrence comparison",
			"benchmark summary records integrator D2D before-after comparison");
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
