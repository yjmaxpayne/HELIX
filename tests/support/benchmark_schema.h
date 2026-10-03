#pragma once

#include <helix/helix.h>

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace helix::test::benchmark {

constexpr const char* kSchemaVersion = "helix.benchmark.v1";

struct ValidationError {
	std::string path;
	std::string message;
};

struct BenchmarkHelix {
	std::string version = "v0.0.3";
	std::string versionSource = "build";
	std::string gitCommit = "unknown";
	std::optional<bool> gitDirty;
};

struct BenchmarkBuild {
	std::string type = "Release";
	std::string cudaArchitectures = "89";
	std::string compiler = "unknown";
};

struct BenchmarkHost {
	std::string os = "linux";
	std::string runner = "local";
};

struct BenchmarkGpu {
	std::string name = "unknown";
	int device = 0;
	std::string driver = "unknown";
	long long memoryTotalBytes = 0;
};

struct BenchmarkCuda {
	std::string runtimeVersion = "unknown";
	std::string driverVersion = "unknown";
};

struct BenchmarkCase {
	std::string name = "legacy_spin_glass_default";
	std::string backend = "LegacyCudaSparse";
	std::string precision = "single";
	std::string resultMode = "FinalState";
};

struct BenchmarkProblem {
	std::size_t hilbertSize = 1024;
	std::size_t kMax = 2;
	std::size_t jMax = 3;
	std::size_t hierarchySize = 10;
	double timeStep = 0.1;
	int integrationOrder = 4;
	std::size_t steps = 100;
	std::size_t warmupSteps = 1;
	std::size_t steadySteps = 99;
};

struct BenchmarkTiming {
	double init = 0.0;
	double warmup = 0.0;
	double steadyPropagation = 0.0;
	double resultExtraction = 0.0;
	double teardown = 0.0;
	std::string steadyPropagationScope = "excludes_init_warmup_result_extraction";
};

struct BenchmarkMeasurementScopes {
	std::string mainMeasurementScope = "benchmark.main";
	std::string mainMeasurementStatus = "captured";
	std::string calibrationScope = "benchmark.calibration";
	std::string calibrationStatus = "captured";
	bool calibrationCaptured = true;
	bool calibrationExcludedFromMain = true;
	std::string nvtxNamingConvention =
		"benchmark.main.init,benchmark.main.warmup,benchmark.main.steady_propagation,"
		"benchmark.main.result_extraction,benchmark.main.teardown,benchmark.calibration";
};

struct BenchmarkMemory {
	long long peakDeviceBytes = 0;
	long long deviceDeltaBytes = 0;
	std::string measurementMethod = "cudaMemGetInfo_delta";
};

struct BenchmarkDiagnosticsMirror {
	std::string backend = "LegacyCudaSparse";
	std::string precision = "single";
	std::size_t hilbertSize = 1024;
	std::size_t hierarchySize = 10;
	std::size_t steps = 100;
	double timeStep = 0.1;
	int integrationOrder = 4;
	std::string status = "Success";
};

struct BenchmarkGates {
	std::string correctnessGateStatus = "not_run";
	std::string baselineGateStatus = "not_run";
};

struct BenchmarkEvidenceField {
	std::string name;
	std::string value;
	std::string unit;
};

struct BenchmarkCounterMetric {
	std::string unit;
	std::optional<double> doubleValue;
	std::optional<long long> integerValue;

	bool collected() const noexcept
	{
		return doubleValue.has_value() || integerValue.has_value();
	}
};

inline BenchmarkCounterMetric notCollectedCounter(std::string unit)
{
	BenchmarkCounterMetric metric;
	metric.unit = std::move(unit);
	return metric;
}

inline BenchmarkCounterMetric collectedCounter(double value, std::string unit)
{
	BenchmarkCounterMetric metric;
	metric.unit = std::move(unit);
	metric.doubleValue = value;
	return metric;
}

inline BenchmarkCounterMetric collectedCounter(long long value, std::string unit)
{
	BenchmarkCounterMetric metric;
	metric.unit = std::move(unit);
	metric.integerValue = value;
	return metric;
}

struct BenchmarkSpmmCounters {
	BenchmarkCounterMetric callCount = notCollectedCounter("count");
	BenchmarkCounterMetric timeMs = notCollectedCounter("ms");
	BenchmarkCounterMetric descriptorCreateCount = notCollectedCounter("count");
	BenchmarkCounterMetric workspaceAllocCount = notCollectedCounter("count");
	BenchmarkCounterMetric workspaceBytes = notCollectedCounter("bytes");
	BenchmarkCounterMetric bufferSizeQueryCount = notCollectedCounter("count");
};

struct BenchmarkTransposeCounters {
	BenchmarkCounterMetric callCount = notCollectedCounter("count");
	BenchmarkCounterMetric timeMs = notCollectedCounter("ms");
	BenchmarkCounterMetric bytes = notCollectedCounter("bytes");
};

struct BenchmarkD2DCopyCounters {
	BenchmarkCounterMetric copyCount = notCollectedCounter("count");
	BenchmarkCounterMetric timeMs = notCollectedCounter("ms");
	BenchmarkCounterMetric bytes = notCollectedCounter("bytes");
};

struct BenchmarkSyncCounters {
	BenchmarkCounterMetric deviceSynchronizeCount = notCollectedCounter("count");
	BenchmarkCounterMetric syncWaitMs = notCollectedCounter("ms");
};

struct BenchmarkResultExtractionCounters {
	BenchmarkCounterMetric syncWaitMs = notCollectedCounter("ms");
	BenchmarkCounterMetric hostAllocationMs = notCollectedCounter("ms");
	BenchmarkCounterMetric d2hCopyMs = notCollectedCounter("ms");
	BenchmarkCounterMetric conversionMs = notCollectedCounter("ms");
	BenchmarkCounterMetric d2hBytes = notCollectedCounter("bytes");
	BenchmarkCounterMetric elementCount = notCollectedCounter("count");
};

struct BenchmarkProfilingCounters {
	BenchmarkSpmmCounters spmm;
	BenchmarkTransposeCounters transpose;
	BenchmarkD2DCopyCounters d2dCopy;
	BenchmarkSyncCounters sync;
	BenchmarkResultExtractionCounters resultExtraction;
};

struct BenchmarkHypothesisEvidence {
	std::string id;
	std::string name;
	std::string status;
	std::vector<BenchmarkEvidenceField> fields;
	std::string method;
	std::string interpretation;
	std::string downstreamAction;
};

struct BenchmarkProfiling {
	std::string timingMode = "attribution";
	std::vector<std::string> instrumentation = {"runner_wall_clock"};
	bool nvtxEnabled = false;
	std::optional<std::string> nsightArtifact;
	BenchmarkProfilingCounters counters;
	std::vector<BenchmarkHypothesisEvidence> hypotheses;
};

struct BenchmarkRecord {
	std::string schemaVersion = kSchemaVersion;
	std::string runId = "20260513T000000Z-unknown-sm89";
	std::string timestampUtc = "2026-05-13T00:00:00Z";
	BenchmarkHelix helix;
	BenchmarkBuild build;
	BenchmarkHost host;
	BenchmarkGpu gpu;
	BenchmarkCuda cuda;
	BenchmarkCase caseInfo;
	BenchmarkProblem problem;
	BenchmarkTiming timing;
	BenchmarkMeasurementScopes measurementScopes;
	BenchmarkMemory memory;
	std::optional<BenchmarkDiagnosticsMirror> diagnostics = BenchmarkDiagnosticsMirror{};
	BenchmarkGates gates;
	BenchmarkProfiling profiling;
	std::string notes;
};

struct BenchmarkMetricStats {
	std::size_t count = 0;
	double minimum = 0.0;
	double maximum = 0.0;
	double median = 0.0;
	double sampleStddev = 0.0;
};

enum class BenchmarkBeforeAfterConclusion {
	OverallImproved,
	OverallRegressed,
	WithinNoise,
	InconclusiveDueToVarianceOrBuildMismatch
};

inline const char* toString(BenchmarkBeforeAfterConclusion conclusion) noexcept
{
	switch(conclusion)
	{
	case BenchmarkBeforeAfterConclusion::OverallImproved:
		return "overall_improved";
	case BenchmarkBeforeAfterConclusion::OverallRegressed:
		return "overall_regressed";
	case BenchmarkBeforeAfterConclusion::WithinNoise:
		return "within_noise";
	case BenchmarkBeforeAfterConclusion::InconclusiveDueToVarianceOrBuildMismatch:
		return "inconclusive_due_to_variance_or_build_mismatch";
	}
	return "inconclusive_due_to_variance_or_build_mismatch";
}

inline BenchmarkMetricStats summarizeBenchmarkSamples(std::vector<double> samples)
{
	BenchmarkMetricStats stats;
	stats.count = samples.size();
	if(samples.empty())
	{
		return stats;
	}

	std::sort(samples.begin(), samples.end());
	stats.minimum = samples.front();
	stats.maximum = samples.back();
	const std::size_t middle = samples.size() / 2;
	if(samples.size() % 2 == 0)
	{
		stats.median = (samples[middle - 1] + samples[middle]) / 2.0;
	}
	else
	{
		stats.median = samples[middle];
	}

	double sum = 0.0;
	for(double sample : samples)
	{
		sum += sample;
	}
	const double mean = sum / static_cast<double>(samples.size());
	double squaredDeviationSum = 0.0;
	for(double sample : samples)
	{
		const double deviation = sample - mean;
		squaredDeviationSum += deviation * deviation;
	}
	stats.sampleStddev = samples.size() > 1
		? std::sqrt(squaredDeviationSum / static_cast<double>(samples.size() - 1))
		: 0.0;
	return stats;
}

inline double benchmarkMainTotalMs(const BenchmarkTiming& timing)
{
	return timing.init + timing.warmup + timing.steadyPropagation
		+ timing.resultExtraction + timing.teardown;
}

inline double steadyPropagationMsPerStep(const BenchmarkRecord& record)
{
	if(record.problem.steadySteps == 0)
	{
		return 0.0;
	}
	return record.timing.steadyPropagation / static_cast<double>(record.problem.steadySteps);
}

inline BenchmarkBeforeAfterConclusion classifyBenchmarkPostPreRatio(double postPreRatio,
	double relativeNoise,
	bool comparableBuild)
{
	if(!comparableBuild
		|| !std::isfinite(postPreRatio)
		|| !std::isfinite(relativeNoise)
		|| postPreRatio <= 0.0
		|| relativeNoise >= 0.10)
	{
		return BenchmarkBeforeAfterConclusion::InconclusiveDueToVarianceOrBuildMismatch;
	}

	const double noiseBand = std::max(0.02, relativeNoise * 2.0);
	if(std::abs(postPreRatio - 1.0) <= noiseBand)
	{
		return BenchmarkBeforeAfterConclusion::WithinNoise;
	}
	if(postPreRatio < 1.0)
	{
		return BenchmarkBeforeAfterConclusion::OverallImproved;
	}
	return BenchmarkBeforeAfterConclusion::OverallRegressed;
}

inline const char* toString(Backend backend) noexcept
{
	switch(backend)
	{
	case Backend::LegacyCudaSparse:
		return "LegacyCudaSparse";
	case Backend::CudaSparse:
		return "CudaSparse";
	case Backend::CpuReference:
		return "CpuReference";
	}
	return "unknown";
}

inline const char* toString(Precision precision) noexcept
{
	switch(precision)
	{
	case Precision::Single:
		return "single";
	case Precision::Double:
		return "double";
	}
	return "unknown";
}

inline const char* toString(ResultMode mode) noexcept
{
	switch(mode)
	{
	case ResultMode::FinalState:
		return "FinalState";
	case ResultMode::ObservableTrace:
		return "ObservableTrace";
	case ResultMode::Trajectory:
		return "Trajectory";
	}
	return "unknown";
}

inline const char* toString(RunStatus status) noexcept
{
	switch(status)
	{
	case RunStatus::NotStarted:
		return "NotStarted";
	case RunStatus::Success:
		return "Success";
	case RunStatus::Failed:
		return "Failed";
	}
	return "unknown";
}

inline BenchmarkDiagnosticsMirror mirrorDiagnostics(const Diagnostics& diagnostics)
{
	BenchmarkDiagnosticsMirror mirror;
	mirror.backend = toString(diagnostics.backend);
	mirror.precision = toString(diagnostics.precision);
	mirror.hilbertSize = diagnostics.hilbertSize;
	mirror.hierarchySize = diagnostics.hierarchySize;
	mirror.steps = diagnostics.steps;
	mirror.timeStep = diagnostics.timeStep;
	mirror.integrationOrder = diagnostics.integrationOrder;
	mirror.status = toString(diagnostics.status);
	return mirror;
}

inline std::string fixedMilliseconds(double value)
{
	std::ostringstream output;
	output << std::fixed << std::setprecision(3) << value;
	return output.str();
}

inline std::string nsightArtifactSummaryValue(const std::optional<std::string>& nsightArtifact)
{
	if(nsightArtifact.has_value() && !nsightArtifact->empty())
	{
		return *nsightArtifact;
	}
	return "not_collected";
}

inline BenchmarkEvidenceField evidenceField(std::string name, std::string value, std::string unit = "")
{
	return {std::move(name), std::move(value), std::move(unit)};
}

inline std::string counterSummary(const BenchmarkCounterMetric& metric)
{
	if(metric.integerValue.has_value())
	{
		return std::to_string(*metric.integerValue);
	}
	if(metric.doubleValue.has_value())
	{
		return fixedMilliseconds(*metric.doubleValue);
	}
	return "not_collected";
}

inline BenchmarkProfilingCounters sampleProfilingCounters(const BenchmarkProblem& problem)
{
	BenchmarkProfilingCounters counters;
	counters.sync.deviceSynchronizeCount = collectedCounter(1LL, "count");
	counters.sync.syncWaitMs = collectedCounter(0.0, "ms");
	counters.resultExtraction.syncWaitMs = collectedCounter(0.0, "ms");
	counters.resultExtraction.hostAllocationMs = collectedCounter(0.0, "ms");
	counters.resultExtraction.d2hCopyMs = collectedCounter(0.0, "ms");
	counters.resultExtraction.conversionMs = collectedCounter(0.0, "ms");
	counters.resultExtraction.elementCount =
		collectedCounter(static_cast<long long>(problem.hilbertSize * problem.hilbertSize), "count");
	counters.resultExtraction.d2hBytes =
		collectedCounter(static_cast<long long>(problem.hilbertSize * problem.hilbertSize * 8), "bytes");
	return counters;
}

inline std::vector<BenchmarkHypothesisEvidence> defaultProfilingEvidenceSlots(const BenchmarkTiming& timing,
	const BenchmarkMemory&,
	const BenchmarkProfilingCounters& counters)
{
	std::vector<BenchmarkHypothesisEvidence> slots;
	const bool spmmCollected =
		counters.spmm.callCount.collected()
		|| counters.spmm.timeMs.collected()
		|| counters.spmm.descriptorCreateCount.collected()
		|| counters.spmm.workspaceAllocCount.collected()
		|| counters.spmm.workspaceBytes.collected()
		|| counters.spmm.bufferSizeQueryCount.collected();
	const bool resultExtractionCollected =
		counters.resultExtraction.syncWaitMs.collected()
		|| counters.resultExtraction.hostAllocationMs.collected()
		|| counters.resultExtraction.d2hCopyMs.collected()
		|| counters.resultExtraction.conversionMs.collected()
		|| counters.resultExtraction.d2hBytes.collected()
		|| counters.resultExtraction.elementCount.collected();
	const bool transposeCollected =
		counters.transpose.callCount.collected()
		|| counters.transpose.timeMs.collected()
		|| counters.transpose.bytes.collected();
	const bool d2dCopyCollected =
		counters.d2dCopy.copyCount.collected() || counters.d2dCopy.bytes.collected();
	const bool layoutHotspotCollected = transposeCollected || d2dCopyCollected;
	std::string h005Method =
		"reserved evidence slot for future internal counters or optional NVTX markers";
	std::string h005Interpretation =
		"No transpose/layout hotspot data is collected by the current runner.";
	std::string h005DownstreamAction =
		"Instrument transpose/layout markers in PLAN-T7 or backend redesign profiling runs.";
	if(transposeCollected && d2dCopyCollected)
	{
		h005Method =
			"transpose wrapper counters and integrator D2D copy counters captured in the steady propagation scope; transpose timing remains not_collected unless measured without adding stream synchronization";
		h005Interpretation =
			"Physical transpose call count/bytes and integrator full-hierarchy D2D count/bytes are collected; transpose time is intentionally deferred to avoid adding synchronization to the production path.";
		h005DownstreamAction =
			"Use the collected counts/bytes and layout option matrix to keep public row-major order while deferring descriptor-order rewrites to a separate correctness gate.";
	}
	else if(transposeCollected)
	{
		h005Method =
			"transpose wrapper counters captured in the steady propagation scope; transpose timing remains not_collected unless measured without adding stream synchronization";
		h005Interpretation =
			"Physical transpose call count/bytes are collected; transpose time is intentionally deferred to avoid adding synchronization to the production path.";
		h005DownstreamAction =
			"Use the collected transpose counts/bytes to gate layout decisions and defer timing to Nsight or event-based profiling work.";
	}
	else if(d2dCopyCollected)
	{
		h005Method = "integrator D2D copy counters captured in the steady propagation scope; transpose counters remain deferred";
		h005Interpretation =
			"Integrator full-hierarchy copy count and bytes are collected; transpose/layout hotspot data is still deferred to PLAN-T7.";
		h005DownstreamAction =
			"Use D2D copy count/bytes to gate recurrence buffer changes; instrument transpose/layout markers in PLAN-T7.";
	}
	slots.push_back({
		"H-001",
		"descriptor/workspace rebuild cost",
		spmmCollected ? "collected" : "not_collected",
		{
			evidenceField("context_init_ms", fixedMilliseconds(timing.init), "ms"),
			evidenceField("spmm_call_count", counterSummary(counters.spmm.callCount), "count"),
			evidenceField("descriptor_create_count", counterSummary(counters.spmm.descriptorCreateCount), "count"),
			evidenceField("buffer_size_query_count", counterSummary(counters.spmm.bufferSizeQueryCount), "count"),
			evidenceField("workspace_alloc_count", counterSummary(counters.spmm.workspaceAllocCount), "count"),
			evidenceField("workspace_bytes", counterSummary(counters.spmm.workspaceBytes), "bytes"),
			evidenceField("spmm_time_ms", counterSummary(counters.spmm.timeMs), "ms"),
			evidenceField("structured_v_specialization_decision", "defer_legacy_spin_glass_only"),
			evidenceField("structured_v_generic_sparse_contract",
				"unaffected:System::from_sparse_validation_only")
		},
		spmmCollected
			? "private CudaSparseBackendPlan SpMM counters captured in the steady propagation scope after warmup"
			: "backend SpMM counters were disabled for pure timing; rerun attribution mode to collect this evidence",
		spmmCollected
			? "Descriptor creation, workspace allocation, buffer-size query, and SpMM call counters are separated from aggregate timing; warmed compatible calls should report zero setup counters. Structured V replacement remains deferred as a legacy spin-glass-only kernel decision, not a generic sparse contract."
			: "Pure timing records wall-clock phases only, so descriptor/workspace attribution is intentionally unavailable in this record.",
		spmmCollected
			? "Keep System::from_sparse() validation-only unchanged; revisit structured V only behind a private legacy adapter with reference-kernel, benchmark, and baseline gates."
			: "Use pure timing for release comparisons and attribution mode for backend counter diagnosis."
	});
	slots.push_back({
		"H-002",
		"host copy / result extraction cost",
		resultExtractionCollected ? "collected" : "not_collected",
		{
			evidenceField("result_extraction_ms", fixedMilliseconds(timing.resultExtraction), "ms"),
			evidenceField("sync_wait_ms", counterSummary(counters.resultExtraction.syncWaitMs), "ms"),
			evidenceField("host_allocation_ms", counterSummary(counters.resultExtraction.hostAllocationMs), "ms"),
			evidenceField("d2h_copy_ms", counterSummary(counters.resultExtraction.d2hCopyMs), "ms"),
			evidenceField("conversion_ms", counterSummary(counters.resultExtraction.conversionMs), "ms"),
			evidenceField("d2h_bytes", counterSummary(counters.resultExtraction.d2hBytes), "bytes"),
			evidenceField("element_count", counterSummary(counters.resultExtraction.elementCount), "count"),
			evidenceField("result_extraction_entrypoint", "helix::Context::reduced_density")
		},
		resultExtractionCollected
			? "internal ResultExtractor substage counters captured by the private backend profiling sink"
			: "result extraction substage counters were disabled for pure timing; aggregate result extraction wall-clock remains available",
		resultExtractionCollected
			? "Result extraction is split into sync wait, host allocation, D2H copy, conversion, bytes, and element count."
			: "Pure timing keeps result extraction in the phase timing total but does not collect substage attribution.",
		resultExtractionCollected
			? "Use the substage distribution to decide whether final-state extraction needs buffer/layout changes."
			: "Use attribution mode only when substage diagnosis is needed."
	});
	slots.push_back({
		"H-003",
		"device-wide sync serialization",
		"inconclusive",
		{
			evidenceField("runner_phase_boundary_sync_count", "10", "count"),
			evidenceField("internal_device_synchronize_count",
				counterSummary(counters.sync.deviceSynchronizeCount),
				"count"),
			evidenceField("internal_sync_wait_ms", counterSummary(counters.sync.syncWaitMs), "ms"),
			evidenceField("known_sync_locations",
				"before/after init,warmup,steady_propagation,result_extraction,teardown"),
			evidenceField("sync_audit_sites",
				"measureCudaPhase,LegacyRuntimeSession::run_steps,develop,getdRhoSparse,clearLiouvilleStorage"),
			evidenceField("event_replacement_plan", "required_before_removing_sync"),
			evidenceField("cuda_graph_decision", "defer_fixed_shape_capture")
		},
		"explicit runner cudaDeviceSynchronize calls around each measured phase plus static audit of production synchronization sites",
		"Production hot-path synchronizations remain correctness and error boundaries; replacing them requires explicit stream/event dependencies before fixed-shape graph capture is credible.",
		"Implement and test event dependencies for develop/getdRhoSparse first, then run a dedicated CUDA Graph capture spike."
	});
	slots.push_back({
		"H-004",
		"stream/handle ownership cost",
		"inconclusive",
		{
			evidenceField("context_init_ms", fixedMilliseconds(timing.init), "ms"),
			evidenceField("stream_count", "not_collected", "count"),
			evidenceField("cublas_handle_count", "not_collected", "count"),
			evidenceField("cusparse_handle_count", "not_collected", "count")
		},
		"runner wall-clock timing around Context construction; no public API profiling sink is enabled",
		"Handle ownership cost is only visible through aggregate init timing in this P0 evidence.",
		"Add opt-in internal handle lifetime counters outside public headers."
	});
	slots.push_back({
		"H-005",
		"D2D copy / transpose hotspot",
		layoutHotspotCollected ? "collected" : "not_collected",
		{
			evidenceField("transpose_count", counterSummary(counters.transpose.callCount), "count"),
			evidenceField("transpose_time_ms", counterSummary(counters.transpose.timeMs), "ms"),
			evidenceField("transpose_bytes", counterSummary(counters.transpose.bytes), "bytes"),
			evidenceField("d2d_copy_count", counterSummary(counters.d2dCopy.copyCount), "count"),
			evidenceField("d2d_copy_time_ms", counterSummary(counters.d2dCopy.timeMs), "ms"),
			evidenceField("d2d_copy_bytes", counterSummary(counters.d2dCopy.bytes), "bytes"),
			evidenceField("future_marker_names", "transpose_initial_rho,transpose_density_snapshot")
		},
		h005Method,
		h005Interpretation,
		h005DownstreamAction
	});
	return slots;
}

inline BenchmarkRecord sampleLegacySpinGlassRecord()
{
	BenchmarkRecord record;
	record.caseInfo.backend = toString(Backend::LegacyCudaSparse);
	record.caseInfo.precision = toString(Precision::Single);
	record.caseInfo.resultMode = toString(ResultMode::FinalState);
	record.diagnostics = BenchmarkDiagnosticsMirror{
		record.caseInfo.backend,
		record.caseInfo.precision,
		record.problem.hilbertSize,
		record.problem.hierarchySize,
		record.problem.steps,
		record.problem.timeStep,
		record.problem.integrationOrder,
		toString(RunStatus::Success)
	};
	record.profiling.counters = sampleProfilingCounters(record.problem);
	record.profiling.hypotheses =
		defaultProfilingEvidenceSlots(record.timing, record.memory, record.profiling.counters);
	return record;
}

inline bool contains(const std::vector<std::string>& values, const std::string& value)
{
	return std::find(values.begin(), values.end(), value) != values.end();
}

inline void addError(std::vector<ValidationError>& errors, std::string path, std::string message)
{
	errors.push_back({std::move(path), std::move(message)});
}

inline void requireString(std::vector<ValidationError>& errors,
	const std::string& value,
	const char* path,
	const char* description)
{
	if(value.empty())
	{
		addError(errors, path, description);
	}
}

inline void requireNonNegative(std::vector<ValidationError>& errors, double value, const char* path)
{
	if(value < 0.0)
	{
		addError(errors, path, "value must be non-negative");
	}
}

inline void requireNonNegative(std::vector<ValidationError>& errors, long long value, const char* path)
{
	if(value < 0)
	{
		addError(errors, path, "value must be non-negative");
	}
}

inline void validateCounterMetric(std::vector<ValidationError>& errors,
	const BenchmarkCounterMetric& metric,
	const std::string& path)
{
	if(metric.unit.empty())
	{
		addError(errors, path + ".unit", "counter unit is required");
	}
	if(metric.doubleValue.has_value() && metric.integerValue.has_value())
	{
		addError(errors, path, "counter must not contain both double and integer values");
	}
	if(metric.doubleValue.has_value())
	{
		requireNonNegative(errors, *metric.doubleValue, path.c_str());
	}
	if(metric.integerValue.has_value())
	{
		requireNonNegative(errors, *metric.integerValue, path.c_str());
	}
}

inline void validateProfilingCounters(std::vector<ValidationError>& errors, const BenchmarkProfilingCounters& counters)
{
	validateCounterMetric(errors, counters.spmm.callCount, "profiling.counters.spmm.call_count");
	validateCounterMetric(errors, counters.spmm.timeMs, "profiling.counters.spmm.time_ms");
	validateCounterMetric(errors,
		counters.spmm.descriptorCreateCount,
		"profiling.counters.spmm.descriptor_create_count");
	validateCounterMetric(errors,
		counters.spmm.workspaceAllocCount,
		"profiling.counters.spmm.workspace_alloc_count");
	validateCounterMetric(errors, counters.spmm.workspaceBytes, "profiling.counters.spmm.workspace_bytes");
	validateCounterMetric(errors,
		counters.spmm.bufferSizeQueryCount,
		"profiling.counters.spmm.buffer_size_query_count");

	validateCounterMetric(errors, counters.transpose.callCount, "profiling.counters.transpose.call_count");
	validateCounterMetric(errors, counters.transpose.timeMs, "profiling.counters.transpose.time_ms");
	validateCounterMetric(errors, counters.transpose.bytes, "profiling.counters.transpose.bytes");

	validateCounterMetric(errors, counters.d2dCopy.copyCount, "profiling.counters.d2d_copy.copy_count");
	validateCounterMetric(errors, counters.d2dCopy.timeMs, "profiling.counters.d2d_copy.time_ms");
	validateCounterMetric(errors, counters.d2dCopy.bytes, "profiling.counters.d2d_copy.bytes");

	validateCounterMetric(errors, counters.sync.deviceSynchronizeCount,
		"profiling.counters.sync.device_synchronize_count");
	validateCounterMetric(errors, counters.sync.syncWaitMs, "profiling.counters.sync.sync_wait_ms");

	validateCounterMetric(errors,
		counters.resultExtraction.syncWaitMs,
		"profiling.counters.result_extraction.sync_wait_ms");
	validateCounterMetric(errors,
		counters.resultExtraction.hostAllocationMs,
		"profiling.counters.result_extraction.host_allocation_ms");
	validateCounterMetric(errors,
		counters.resultExtraction.d2hCopyMs,
		"profiling.counters.result_extraction.d2h_copy_ms");
	validateCounterMetric(errors,
		counters.resultExtraction.conversionMs,
		"profiling.counters.result_extraction.conversion_ms");
	validateCounterMetric(errors,
		counters.resultExtraction.d2hBytes,
		"profiling.counters.result_extraction.d2h_bytes");
	validateCounterMetric(errors,
		counters.resultExtraction.elementCount,
		"profiling.counters.result_extraction.element_count");
}

inline bool validate(const BenchmarkRecord& record, std::vector<ValidationError>& errors)
{
	errors.clear();

	if(record.schemaVersion != kSchemaVersion)
	{
		addError(errors, "schema_version", "schema_version must be helix.benchmark.v1");
	}

	requireString(errors, record.runId, "run_id", "run_id is required");
	requireString(errors, record.timestampUtc, "timestamp_utc", "timestamp_utc is required");
	requireString(errors, record.helix.version, "helix.version", "HELIX version is required");
	requireString(errors, record.helix.versionSource, "helix.version_source", "HELIX version source is required");
	requireString(errors, record.helix.gitCommit, "helix.git_commit", "git commit is required");
	requireString(errors, record.build.type, "build.type", "build type is required");
	requireString(errors, record.build.cudaArchitectures, "build.cuda_architectures", "CUDA architectures are required");
	requireString(errors, record.build.compiler, "build.compiler", "compiler is required");
	requireString(errors, record.host.os, "host.os", "host OS is required");
	requireString(errors, record.host.runner, "host.runner", "host runner is required");
	requireString(errors, record.gpu.name, "gpu.name", "GPU name is required");
	requireString(errors, record.gpu.driver, "gpu.driver", "GPU driver is required");
	requireString(errors, record.cuda.runtimeVersion, "cuda.runtime_version", "CUDA runtime version is required");
	requireString(errors, record.cuda.driverVersion, "cuda.driver_version", "CUDA driver version is required");
	requireString(errors, record.caseInfo.name, "case.name", "case name is required");

	const std::vector<std::string> backendValues = {"LegacyCudaSparse", "CudaSparse", "CpuReference"};
	const std::vector<std::string> precisionValues = {"single", "double"};
	const std::vector<std::string> resultModeValues = {"FinalState", "ObservableTrace", "Trajectory"};
	const std::vector<std::string> statusValues = {"NotStarted", "Success", "Failed"};
	const std::vector<std::string> gateStatusValues = {"not_run", "passed", "failed"};
	const std::vector<std::string> scopeStatusValues = {"captured", "not_captured"};
	const std::vector<std::string> evidenceStatusValues = {
		"not_collected", "collected", "inconclusive", "supported", "not_supported"};
	const std::vector<std::string> timingModeValues = {"pure_timing", "attribution"};
	const std::vector<std::string> requiredEvidenceIds = {"H-001", "H-002", "H-003", "H-004", "H-005"};
	const std::vector<std::string> memoryMethods = {"cudaMemGetInfo_delta"};

	if(!contains(backendValues, record.caseInfo.backend))
	{
		addError(errors, "case.backend", "backend must match a public helix::Backend value");
	}
	if(!contains(precisionValues, record.caseInfo.precision))
	{
		addError(errors, "case.precision", "precision must match a public helix::Precision value");
	}
	if(!contains(resultModeValues, record.caseInfo.resultMode))
	{
		addError(errors, "case.result_mode", "result_mode must match a public helix::ResultMode value");
	}

	if(record.problem.hilbertSize == 0)
	{
		addError(errors, "problem.N", "Hilbert size must be positive");
	}
	if(record.problem.hierarchySize == 0)
	{
		addError(errors, "problem.hierarchy_size", "hierarchy size must be positive");
	}
	if(record.problem.steps != record.problem.warmupSteps + record.problem.steadySteps)
	{
		addError(errors, "problem.steps", "steps must equal warmup_steps + steady_steps");
	}
	if(record.problem.timeStep <= 0.0)
	{
		addError(errors, "problem.time_step", "time_step must be positive");
	}
	if(record.problem.integrationOrder <= 0)
	{
		addError(errors, "problem.integration_order", "integration_order must be positive");
	}

	requireNonNegative(errors, record.timing.init, "timing_ms.init");
	requireNonNegative(errors, record.timing.warmup, "timing_ms.warmup");
	requireNonNegative(errors, record.timing.steadyPropagation, "timing_ms.steady_propagation");
	requireNonNegative(errors, record.timing.resultExtraction, "timing_ms.result_extraction");
	requireNonNegative(errors, record.timing.teardown, "timing_ms.teardown");
	if(record.timing.steadyPropagationScope != "excludes_init_warmup_result_extraction")
	{
		addError(errors,
			"timing_ms.steady_propagation_scope",
			"steady propagation must explicitly exclude init, warmup, and result extraction");
	}

	requireString(errors,
		record.measurementScopes.mainMeasurementScope,
		"measurement_scope.main_measurement_scope",
		"main measurement scope is required");
	requireString(errors,
		record.measurementScopes.calibrationScope,
		"measurement_scope.calibration_scope",
		"calibration scope is required");
	requireString(errors,
		record.measurementScopes.nvtxNamingConvention,
		"measurement_scope.nvtx_naming_convention",
		"NVTX naming convention is required");
	if(!contains(scopeStatusValues, record.measurementScopes.mainMeasurementStatus))
	{
		addError(errors, "measurement_scope.main_measurement_status", "main measurement status is not recognized");
	}
	else if(record.measurementScopes.mainMeasurementStatus != "captured")
	{
		addError(errors, "measurement_scope.main_measurement_status", "main measurement must be captured");
	}
	if(!contains(scopeStatusValues, record.measurementScopes.calibrationStatus))
	{
		addError(errors, "measurement_scope.calibration_status", "calibration status is not recognized");
	}
	else if((record.measurementScopes.calibrationStatus == "captured")
		!= record.measurementScopes.calibrationCaptured)
	{
		addError(errors,
			"measurement_scope.calibration_captured",
			"calibration capture flag must match calibration status");
	}
	if(!record.measurementScopes.calibrationExcludedFromMain)
	{
		addError(errors,
			"measurement_scope.calibration_excluded_from_main",
			"calibration must be excluded from main aggregation");
	}

	requireNonNegative(errors, record.gpu.memoryTotalBytes, "gpu.memory_total_bytes");
	requireNonNegative(errors, record.memory.peakDeviceBytes, "memory.peak_device_bytes");
	requireNonNegative(errors, record.memory.deviceDeltaBytes, "memory.device_delta_bytes");
	if(!contains(memoryMethods, record.memory.measurementMethod))
	{
		addError(errors, "memory.measurement_method", "memory measurement method is not recognized");
	}
	if(!contains(gateStatusValues, record.gates.correctnessGateStatus))
	{
		addError(errors, "gates.correctness_gate_status", "correctness gate status is not recognized");
	}
	if(!contains(gateStatusValues, record.gates.baselineGateStatus))
	{
		addError(errors, "gates.baseline_gate_status", "baseline gate status is not recognized");
	}

	if(!record.diagnostics.has_value())
	{
		addError(errors, "diagnostics", "diagnostics mirror is required");
		return errors.empty();
	}

	const BenchmarkDiagnosticsMirror& diagnostics = *record.diagnostics;
	if(!contains(backendValues, diagnostics.backend))
	{
		addError(errors, "diagnostics.backend", "diagnostics backend is not recognized");
	}
	if(!contains(precisionValues, diagnostics.precision))
	{
		addError(errors, "diagnostics.precision", "diagnostics precision is not recognized");
	}
	if(!contains(statusValues, diagnostics.status))
	{
		addError(errors, "diagnostics.status", "diagnostics status is not recognized");
	}
	if(diagnostics.backend != record.caseInfo.backend)
	{
		addError(errors, "diagnostics.backend", "diagnostics backend must mirror case.backend");
	}
	if(diagnostics.precision != record.caseInfo.precision)
	{
		addError(errors, "diagnostics.precision", "diagnostics precision must mirror case.precision");
	}
	if(diagnostics.hilbertSize != record.problem.hilbertSize)
	{
		addError(errors, "diagnostics.hilbert_size", "diagnostics Hilbert size must mirror problem.N");
	}
	if(diagnostics.hierarchySize != record.problem.hierarchySize)
	{
		addError(errors, "diagnostics.hierarchy_size", "diagnostics hierarchy size must mirror problem.hierarchy_size");
	}
	if(diagnostics.steps != record.problem.steps)
	{
		addError(errors, "diagnostics.steps", "diagnostics steps must mirror problem.steps");
	}
	if(std::abs(diagnostics.timeStep - record.problem.timeStep) > 1.0e-12)
	{
		addError(errors, "diagnostics.time_step", "diagnostics time_step must mirror problem.time_step");
	}
	if(diagnostics.integrationOrder != record.problem.integrationOrder)
	{
		addError(errors, "diagnostics.integration_order", "diagnostics integration_order must mirror problem.integration_order");
	}

	if(record.profiling.instrumentation.empty())
	{
		addError(errors, "profiling.instrumentation", "at least one instrumentation method is required");
	}
	if(!contains(timingModeValues, record.profiling.timingMode))
	{
		addError(errors, "profiling.timing_mode", "timing mode must be pure_timing or attribution");
	}
	if(record.profiling.hypotheses.empty())
	{
		addError(errors, "profiling.hypotheses", "profiling hypotheses are required");
	}
	validateProfilingCounters(errors, record.profiling.counters);

	std::vector<std::string> seenEvidenceIds;
	for(std::size_t i = 0; i < record.profiling.hypotheses.size(); ++i)
	{
		const auto& hypothesis = record.profiling.hypotheses[i];
		const std::string base = "profiling.hypotheses[" + std::to_string(i) + "]";
		if(hypothesis.id.empty())
		{
			addError(errors, base + ".id", "hypothesis id is required");
		}
		else
		{
			if(!contains(requiredEvidenceIds, hypothesis.id))
			{
				addError(errors, base + ".id", "hypothesis id must be one of H-001..H-005");
			}
			if(contains(seenEvidenceIds, hypothesis.id))
			{
				addError(errors, base + ".id", "hypothesis id must be unique");
			}
			seenEvidenceIds.push_back(hypothesis.id);
		}
		if(hypothesis.name.empty())
		{
			addError(errors, base + ".name", "hypothesis name is required");
		}
		if(!contains(evidenceStatusValues, hypothesis.status))
		{
			addError(errors, base + ".status", "hypothesis status is not recognized");
		}
		if(hypothesis.fields.empty())
		{
			addError(errors, base + ".fields", "hypothesis fields are required");
		}
		for(std::size_t fieldIndex = 0; fieldIndex < hypothesis.fields.size(); ++fieldIndex)
		{
			const auto& field = hypothesis.fields[fieldIndex];
			const std::string fieldBase = base + ".fields[" + std::to_string(fieldIndex) + "]";
			if(field.name.empty())
			{
				addError(errors, fieldBase + ".name", "evidence field name is required");
			}
			if(field.value.empty())
			{
				addError(errors, fieldBase + ".value", "evidence field value is required");
			}
		}
		if(hypothesis.method.empty())
		{
			addError(errors, base + ".method", "hypothesis method is required");
		}
		if(hypothesis.interpretation.empty())
		{
			addError(errors, base + ".interpretation", "hypothesis interpretation is required");
		}
		if(hypothesis.downstreamAction.empty())
		{
			addError(errors, base + ".downstream_action", "hypothesis downstream action is required");
		}
	}
	for(const auto& id : requiredEvidenceIds)
	{
		if(!contains(seenEvidenceIds, id))
		{
			addError(errors, "profiling.hypotheses." + id, "required profiling evidence slot is missing");
		}
	}

	return errors.empty();
}

inline std::string jsonString(const std::string& value)
{
	std::ostringstream output;
	output << '"';
	for(unsigned char ch : value)
	{
		switch(ch)
		{
		case '"':
			output << "\\\"";
			break;
		case '\\':
			output << "\\\\";
			break;
		case '\n':
			output << "\\n";
			break;
		case '\r':
			output << "\\r";
			break;
		case '\t':
			output << "\\t";
			break;
		default:
			if(ch < 0x20)
			{
				output << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(ch)
					   << std::dec;
			}
			else
			{
				output << static_cast<char>(ch);
			}
			break;
		}
	}
	output << '"';
	return output.str();
}

inline const char* jsonBool(bool value) noexcept
{
	return value ? "true" : "false";
}

inline void writeStringArray(std::ostream& output, const std::vector<std::string>& values)
{
	output << '[';
	for(std::size_t i = 0; i < values.size(); ++i)
	{
		if(i != 0)
		{
			output << ',';
		}
		output << jsonString(values[i]);
	}
	output << ']';
}

inline void writeEvidenceFields(std::ostream& output, const std::vector<BenchmarkEvidenceField>& fields)
{
	output << '[';
	for(std::size_t i = 0; i < fields.size(); ++i)
	{
		if(i != 0)
		{
			output << ',';
		}
		output << '{'
			   << "\"name\":" << jsonString(fields[i].name) << ','
			   << "\"value\":" << jsonString(fields[i].value) << ','
			   << "\"unit\":" << jsonString(fields[i].unit)
			   << '}';
	}
	output << ']';
}

inline void writeHypothesisArray(std::ostream& output, const std::vector<BenchmarkHypothesisEvidence>& hypotheses)
{
	output << '[';
	for(std::size_t i = 0; i < hypotheses.size(); ++i)
	{
		if(i != 0)
		{
			output << ',';
		}
		const auto& hypothesis = hypotheses[i];
		output << '{'
			   << "\"id\":" << jsonString(hypothesis.id) << ','
			   << "\"name\":" << jsonString(hypothesis.name) << ','
			   << "\"status\":" << jsonString(hypothesis.status) << ','
			   << "\"fields\":";
		writeEvidenceFields(output, hypothesis.fields);
		output << ','
			   << "\"method\":" << jsonString(hypothesis.method) << ','
			   << "\"interpretation\":" << jsonString(hypothesis.interpretation) << ','
			   << "\"downstream_action\":" << jsonString(hypothesis.downstreamAction)
			   << '}';
	}
	output << ']';
}

inline void writeCounterMetricValue(std::ostream& output, const BenchmarkCounterMetric& metric)
{
	if(metric.integerValue.has_value())
	{
		output << *metric.integerValue;
	}
	else if(metric.doubleValue.has_value())
	{
		output << *metric.doubleValue;
	}
	else
	{
		output << jsonString("not_collected");
	}
}

inline void writeNamedCounterMetric(std::ostream& output,
	const char* name,
	const BenchmarkCounterMetric& metric,
	bool first)
{
	if(!first)
	{
		output << ',';
	}
	output << jsonString(name) << ':';
	writeCounterMetricValue(output, metric);
}

inline void writeProfilingCounters(std::ostream& output, const BenchmarkProfilingCounters& counters)
{
	output << '{';

	output << "\"spmm\":{";
	writeNamedCounterMetric(output, "call_count", counters.spmm.callCount, true);
	writeNamedCounterMetric(output, "time_ms", counters.spmm.timeMs, false);
	writeNamedCounterMetric(output, "descriptor_create_count", counters.spmm.descriptorCreateCount, false);
	writeNamedCounterMetric(output, "workspace_alloc_count", counters.spmm.workspaceAllocCount, false);
	writeNamedCounterMetric(output, "workspace_bytes", counters.spmm.workspaceBytes, false);
	writeNamedCounterMetric(output, "buffer_size_query_count", counters.spmm.bufferSizeQueryCount, false);
	output << "},";

	output << "\"transpose\":{";
	writeNamedCounterMetric(output, "call_count", counters.transpose.callCount, true);
	writeNamedCounterMetric(output, "time_ms", counters.transpose.timeMs, false);
	writeNamedCounterMetric(output, "bytes", counters.transpose.bytes, false);
	output << "},";

	output << "\"d2d_copy\":{";
	writeNamedCounterMetric(output, "copy_count", counters.d2dCopy.copyCount, true);
	writeNamedCounterMetric(output, "time_ms", counters.d2dCopy.timeMs, false);
	writeNamedCounterMetric(output, "bytes", counters.d2dCopy.bytes, false);
	output << "},";

	output << "\"sync\":{";
	writeNamedCounterMetric(output, "device_synchronize_count", counters.sync.deviceSynchronizeCount, true);
	writeNamedCounterMetric(output, "sync_wait_ms", counters.sync.syncWaitMs, false);
	output << "},";

	output << "\"result_extraction\":{";
	writeNamedCounterMetric(output, "sync_wait_ms", counters.resultExtraction.syncWaitMs, true);
	writeNamedCounterMetric(output, "host_allocation_ms", counters.resultExtraction.hostAllocationMs, false);
	writeNamedCounterMetric(output, "d2h_copy_ms", counters.resultExtraction.d2hCopyMs, false);
	writeNamedCounterMetric(output, "conversion_ms", counters.resultExtraction.conversionMs, false);
	writeNamedCounterMetric(output, "d2h_bytes", counters.resultExtraction.d2hBytes, false);
	writeNamedCounterMetric(output, "element_count", counters.resultExtraction.elementCount, false);
	output << "}";

	output << '}';
}

inline std::string toJsonLine(const BenchmarkRecord& record)
{
	std::ostringstream output;
	output << '{'
		   << "\"schema_version\":" << jsonString(record.schemaVersion) << ','
		   << "\"run_id\":" << jsonString(record.runId) << ','
		   << "\"timestamp_utc\":" << jsonString(record.timestampUtc) << ','
		   << "\"helix\":{"
		   << "\"version\":" << jsonString(record.helix.version) << ','
		   << "\"version_source\":" << jsonString(record.helix.versionSource) << ','
		   << "\"git_commit\":" << jsonString(record.helix.gitCommit) << ','
		   << "\"git_dirty\":";
	if(record.helix.gitDirty.has_value())
	{
		output << jsonBool(*record.helix.gitDirty);
	}
	else
	{
		output << "null";
	}
	output << "},"
		   << "\"build\":{"
		   << "\"type\":" << jsonString(record.build.type) << ','
		   << "\"cuda_architectures\":" << jsonString(record.build.cudaArchitectures) << ','
		   << "\"compiler\":" << jsonString(record.build.compiler) << "},"
		   << "\"host\":{"
		   << "\"os\":" << jsonString(record.host.os) << ','
		   << "\"runner\":" << jsonString(record.host.runner) << "},"
		   << "\"gpu\":{"
		   << "\"name\":" << jsonString(record.gpu.name) << ','
		   << "\"device\":" << record.gpu.device << ','
		   << "\"driver\":" << jsonString(record.gpu.driver) << ','
		   << "\"memory_total_bytes\":" << record.gpu.memoryTotalBytes << "},"
		   << "\"cuda\":{"
		   << "\"runtime_version\":" << jsonString(record.cuda.runtimeVersion) << ','
		   << "\"driver_version\":" << jsonString(record.cuda.driverVersion) << "},"
		   << "\"case\":{"
		   << "\"name\":" << jsonString(record.caseInfo.name) << ','
		   << "\"backend\":" << jsonString(record.caseInfo.backend) << ','
		   << "\"precision\":" << jsonString(record.caseInfo.precision) << ','
		   << "\"result_mode\":" << jsonString(record.caseInfo.resultMode) << "},"
		   << "\"problem\":{"
		   << "\"N\":" << record.problem.hilbertSize << ','
		   << "\"KMax\":" << record.problem.kMax << ','
		   << "\"JMax\":" << record.problem.jMax << ','
		   << "\"hierarchy_size\":" << record.problem.hierarchySize << ','
		   << "\"time_step\":" << record.problem.timeStep << ','
		   << "\"integration_order\":" << record.problem.integrationOrder << ','
		   << "\"steps\":" << record.problem.steps << ','
		   << "\"warmup_steps\":" << record.problem.warmupSteps << ','
		   << "\"steady_steps\":" << record.problem.steadySteps << "},"
		   << "\"timing_ms\":{"
		   << "\"init\":" << record.timing.init << ','
		   << "\"warmup\":" << record.timing.warmup << ','
		   << "\"steady_propagation\":" << record.timing.steadyPropagation << ','
		   << "\"steady_propagation_scope\":" << jsonString(record.timing.steadyPropagationScope) << ','
		   << "\"result_extraction\":" << record.timing.resultExtraction << ','
		   << "\"teardown\":" << record.timing.teardown << "},"
		   << "\"measurement_scope\":{"
		   << "\"main_measurement_scope\":" << jsonString(record.measurementScopes.mainMeasurementScope) << ','
		   << "\"main_measurement_status\":" << jsonString(record.measurementScopes.mainMeasurementStatus) << ','
		   << "\"calibration_scope\":" << jsonString(record.measurementScopes.calibrationScope) << ','
		   << "\"calibration_status\":" << jsonString(record.measurementScopes.calibrationStatus) << ','
		   << "\"calibration_captured\":" << jsonBool(record.measurementScopes.calibrationCaptured) << ','
		   << "\"calibration_excluded_from_main\":"
		   << jsonBool(record.measurementScopes.calibrationExcludedFromMain) << ','
		   << "\"nvtx_naming_convention\":"
		   << jsonString(record.measurementScopes.nvtxNamingConvention) << "},"
		   << "\"memory\":{"
		   << "\"peak_device_bytes\":" << record.memory.peakDeviceBytes << ','
		   << "\"device_delta_bytes\":" << record.memory.deviceDeltaBytes << ','
		   << "\"measurement_method\":" << jsonString(record.memory.measurementMethod) << "},"
		   << "\"diagnostics\":";
	if(record.diagnostics.has_value())
	{
		const BenchmarkDiagnosticsMirror& diagnostics = *record.diagnostics;
		output << '{'
			   << "\"backend\":" << jsonString(diagnostics.backend) << ','
			   << "\"precision\":" << jsonString(diagnostics.precision) << ','
			   << "\"hilbert_size\":" << diagnostics.hilbertSize << ','
			   << "\"hierarchy_size\":" << diagnostics.hierarchySize << ','
			   << "\"steps\":" << diagnostics.steps << ','
			   << "\"time_step\":" << diagnostics.timeStep << ','
			   << "\"integration_order\":" << diagnostics.integrationOrder << ','
			   << "\"status\":" << jsonString(diagnostics.status) << '}';
	}
	else
	{
		output << "null";
	}
	output << ','
		   << "\"gates\":{"
		   << "\"correctness_gate_status\":" << jsonString(record.gates.correctnessGateStatus) << ','
		   << "\"baseline_gate_status\":" << jsonString(record.gates.baselineGateStatus) << "},"
		   << "\"profiling\":{"
		   << "\"timing_mode\":" << jsonString(record.profiling.timingMode) << ','
		   << "\"instrumentation\":";
	writeStringArray(output, record.profiling.instrumentation);
	output << ','
		   << "\"nvtx_enabled\":" << jsonBool(record.profiling.nvtxEnabled) << ','
		   << "\"nsight_artifact\":";
	if(record.profiling.nsightArtifact.has_value())
	{
		output << jsonString(*record.profiling.nsightArtifact);
	}
	else
	{
		output << "null";
	}
	output << ",\"counters\":";
	writeProfilingCounters(output, record.profiling.counters);
	output << ",\"hypotheses\":";
	writeHypothesisArray(output, record.profiling.hypotheses);
	output << "},"
		   << "\"notes\":" << jsonString(record.notes)
		   << "}\n";
	return output.str();
}

} // namespace helix::test::benchmark
