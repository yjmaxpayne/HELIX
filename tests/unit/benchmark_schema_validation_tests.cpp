#include <helix/helix.h>

#include "support/assert.h"
#include "support/benchmark_schema.h"
#include <algorithm>
#include <string>
#include <vector>

namespace {

bool hasErrorAt(const std::vector<helix::test::benchmark::ValidationError>& errors, const char* path)
{
	return std::any_of(errors.begin(), errors.end(), [path](const auto& error) {
		return error.path == path;
	});
}

bool hasEvidenceId(const helix::test::benchmark::BenchmarkRecord& record, const std::string& id)
{
	return std::any_of(record.profiling.hypotheses.begin(),
		record.profiling.hypotheses.end(),
		[&id](const auto& hypothesis) {
			return hypothesis.id == id;
		});
}

const helix::test::benchmark::BenchmarkHypothesisEvidence* findEvidence(
	const helix::test::benchmark::BenchmarkRecord& record,
	const std::string& id)
{
	const auto it = std::find_if(record.profiling.hypotheses.begin(),
		record.profiling.hypotheses.end(),
		[&id](const auto& hypothesis) {
			return hypothesis.id == id;
		});
	return it == record.profiling.hypotheses.end() ? nullptr : &*it;
}

bool evidenceFieldHasValue(const helix::test::benchmark::BenchmarkHypothesisEvidence& evidence,
	const std::string& name,
	const std::string& value)
{
	return std::any_of(evidence.fields.begin(),
		evidence.fields.end(),
		[&](const auto& field) {
			return field.name == name && field.value == value;
		});
}

void expectValid(helix::test::Reporter& reporter,
	const helix::test::benchmark::BenchmarkRecord& record,
	const char* message)
{
	std::vector<helix::test::benchmark::ValidationError> errors;
	reporter.expect(helix::test::benchmark::validate(record, errors), message);
	if(!errors.empty())
	{
		reporter.expect(false, std::string(message) + " has no validation errors");
	}
}

void expectInvalidPath(helix::test::Reporter& reporter,
	helix::test::benchmark::BenchmarkRecord record,
	const char* path,
	const char* message)
{
	std::vector<helix::test::benchmark::ValidationError> errors;
	reporter.expect(!helix::test::benchmark::validate(record, errors), message);
	reporter.expect(hasErrorAt(errors, path), std::string(message) + " reports " + path);
}

void test_enum_strings_match_public_api(helix::test::Reporter& reporter)
{
	using namespace helix::test::benchmark;

	reporter.expect(toString(helix::Backend::LegacyCudaSparse) == "LegacyCudaSparse",
		"LegacyCudaSparse backend enum string is stable");
	reporter.expect(toString(helix::Backend::CudaSparse) == "CudaSparse", "CudaSparse backend enum string is stable");
	reporter.expect(toString(helix::Backend::CpuReference) == "CpuReference",
		"CpuReference backend enum string is stable");
	reporter.expect(toString(helix::Precision::Single) == "single", "single precision enum string is stable");
	reporter.expect(toString(helix::Precision::Double) == "double", "double precision enum string is stable");
	reporter.expect(toString(helix::ResultMode::FinalState) == "FinalState",
		"FinalState result mode enum string is stable");
	reporter.expect(toString(helix::RunStatus::Success) == "Success", "Success status enum string is stable");
}

void test_sample_record_covers_contract(helix::test::Reporter& reporter)
{
	using namespace helix::test::benchmark;

	const BenchmarkRecord record = sampleLegacySpinGlassRecord();
	expectValid(reporter, record, "sample legacy spin-glass benchmark record validates");

	reporter.expect(record.schemaVersion == kSchemaVersion, "sample uses helix.benchmark.v1 schema");
	reporter.expect(record.caseInfo.name == "legacy_spin_glass_default", "sample case name is default legacy spin glass");
	reporter.expect(record.caseInfo.backend == "LegacyCudaSparse", "sample records legacy CUDA sparse backend");
	reporter.expect(record.caseInfo.precision == "single", "sample records single precision");
	reporter.expect(record.problem.hilbertSize == 1024, "sample records N=1024");
	reporter.expect(record.problem.kMax == 2, "sample records KMax=2");
	reporter.expect(record.problem.jMax == 3, "sample records JMax=3");
	reporter.expect(record.problem.hierarchySize == 10, "sample records hierarchy_size=10");
	reporter.expect(record.timing.steadyPropagationScope == "excludes_init_warmup_result_extraction",
		"steady propagation timing explicitly excludes init, warmup, and result extraction");
	reporter.expect(record.measurementScopes.mainMeasurementScope == "benchmark.main",
		"sample records the main measurement scope");
	reporter.expect(record.measurementScopes.mainMeasurementStatus == "captured",
		"sample marks the main measurement scope as captured");
	reporter.expect(record.measurementScopes.calibrationScope == "benchmark.calibration",
		"sample records the calibration scope");
	reporter.expect(record.measurementScopes.calibrationStatus == "captured",
		"sample marks calibration as captured by default");
	reporter.expect(record.measurementScopes.calibrationCaptured,
		"sample records calibration capture state");
	reporter.expect(record.measurementScopes.calibrationExcludedFromMain,
		"sample excludes calibration from main aggregation");
	reporter.expect(record.measurementScopes.nvtxNamingConvention.find("benchmark.main.steady_propagation")
			!= std::string::npos,
		"sample exposes the NVTX naming convention for main steady propagation");
	reporter.expect(record.measurementScopes.nvtxNamingConvention.find("benchmark.calibration")
			!= std::string::npos,
		"sample exposes the NVTX naming convention for calibration");
	reporter.expect(record.diagnostics.has_value(), "sample includes diagnostics mirror");
	reporter.expect(record.diagnostics->backend == record.caseInfo.backend, "diagnostics backend mirrors case backend");
	reporter.expect(record.diagnostics->precision == record.caseInfo.precision,
		"diagnostics precision mirrors case precision");
	reporter.expect(record.diagnostics->hilbertSize == record.problem.hilbertSize,
		"diagnostics hilbert size mirrors problem N");
	reporter.expect(record.diagnostics->hierarchySize == record.problem.hierarchySize,
		"diagnostics hierarchy size mirrors problem hierarchy size");
	reporter.expect(record.diagnostics->steps == record.problem.steps, "diagnostics steps mirror problem steps");
	reporter.expect(record.diagnostics->timeStep == record.problem.timeStep,
		"diagnostics time step mirrors problem time step");
	reporter.expect(record.diagnostics->integrationOrder == record.problem.integrationOrder,
		"diagnostics integration order mirrors problem integration order");
	reporter.expect(record.diagnostics->status == "Success", "diagnostics status is Success");
	reporter.expect(!record.profiling.nsightArtifact.has_value(),
		"sample leaves Nsight artifact unset until manual capture");
	reporter.expect(nsightArtifactSummaryValue(record.profiling.nsightArtifact) == "not_collected",
		"summary value reports not_collected when Nsight capture is absent");
	reporter.expect(record.profiling.hypotheses.size() == 5, "sample contains five profiling hypotheses");
	reporter.expect(!record.profiling.counters.spmm.callCount.collected(),
		"sample keeps SpMM call count explicitly not_collected");
	reporter.expect(record.profiling.counters.resultExtraction.syncWaitMs.collected(),
		"sample records result extraction sync wait counter");
	reporter.expect(record.profiling.counters.resultExtraction.hostAllocationMs.collected(),
		"sample records result extraction host allocation counter");
	reporter.expect(record.profiling.counters.resultExtraction.d2hCopyMs.collected(),
		"sample records result extraction D2H copy counter");
	reporter.expect(record.profiling.counters.resultExtraction.conversionMs.collected(),
		"sample records result extraction conversion counter");
	reporter.expect(record.profiling.counters.resultExtraction.d2hBytes.collected(),
		"sample records result extraction D2H bytes");
	reporter.expect(record.profiling.counters.resultExtraction.elementCount.collected(),
		"sample records result extraction element count");
	reporter.expect(hasEvidenceId(record, "H-001"), "sample contains H-001 evidence slot");
	reporter.expect(hasEvidenceId(record, "H-002"), "sample contains H-002 evidence slot");
	reporter.expect(hasEvidenceId(record, "H-003"), "sample contains H-003 evidence slot");
	reporter.expect(hasEvidenceId(record, "H-004"), "sample contains H-004 evidence slot");
	reporter.expect(hasEvidenceId(record, "H-005"), "sample contains H-005 evidence slot");
	for(const auto& hypothesis : record.profiling.hypotheses)
	{
		reporter.expect(!hypothesis.name.empty(), hypothesis.id + " evidence name is present");
		reporter.expect(!hypothesis.status.empty(), hypothesis.id + " evidence status is present");
		reporter.expect(!hypothesis.fields.empty(), hypothesis.id + " evidence fields are present");
		reporter.expect(!hypothesis.method.empty(), hypothesis.id + " evidence method is present");
		reporter.expect(!hypothesis.interpretation.empty(), hypothesis.id + " evidence interpretation is present");
		reporter.expect(!hypothesis.downstreamAction.empty(), hypothesis.id + " downstream action is present");
	}

	auto mainOnlyRecord = record;
	mainOnlyRecord.measurementScopes.calibrationCaptured = false;
	mainOnlyRecord.measurementScopes.calibrationStatus = "not_captured";
	expectValid(reporter, mainOnlyRecord, "main-only benchmark record validates with calibration not captured");
}

void test_transpose_counters_promote_layout_evidence(helix::test::Reporter& reporter)
{
	using namespace helix::test::benchmark;

	BenchmarkRecord record = sampleLegacySpinGlassRecord();
	record.profiling.counters.transpose.callCount = collectedCounter(12LL, "count");
	record.profiling.counters.transpose.bytes = collectedCounter(1024LL, "bytes");
	record.profiling.hypotheses =
		defaultProfilingEvidenceSlots(record.timing, record.memory, record.profiling.counters);
	expectValid(reporter, record, "benchmark record validates with collected transpose counters");

	const BenchmarkHypothesisEvidence* h005 = findEvidence(record, "H-005");
	reporter.expect(h005 != nullptr, "H-005 evidence exists with transpose counters");
	if(h005 == nullptr)
	{
		return;
	}
	reporter.expect(h005->status == "collected", "H-005 is collected when transpose counters are present");
	reporter.expect(evidenceFieldHasValue(*h005, "transpose_count", "12"),
		"H-005 records collected transpose count");
	reporter.expect(evidenceFieldHasValue(*h005, "transpose_bytes", "1024"),
		"H-005 records collected transpose bytes");
	reporter.expect(h005->method.find("transpose") != std::string::npos,
		"H-005 method explains transpose counter source");
}

void test_sync_audit_evidence_records_graph_decision(helix::test::Reporter& reporter)
{
	using namespace helix::test::benchmark;

	BenchmarkRecord record = sampleLegacySpinGlassRecord();
	const BenchmarkHypothesisEvidence* h003 = findEvidence(record, "H-003");
	reporter.expect(h003 != nullptr, "H-003 evidence exists for synchronization audit");
	if(h003 == nullptr)
	{
		return;
	}
	reporter.expect(evidenceFieldHasValue(*h003, "sync_audit_sites", "measureCudaPhase,LegacyRuntimeSession::run_steps,develop,getdRhoSparse,clearLiouvilleStorage"),
		"H-003 records audited synchronization sites");
	reporter.expect(evidenceFieldHasValue(*h003, "event_replacement_plan", "required_before_removing_sync"),
		"H-003 records event replacement requirement");
	reporter.expect(evidenceFieldHasValue(*h003, "cuda_graph_decision", "defer_fixed_shape_capture"),
		"H-003 records CUDA Graph feasibility decision");
	reporter.expect(h003->downstreamAction.find("CUDA Graph") != std::string::npos,
		"H-003 downstream action names CUDA Graph follow-up");
}

void test_structured_v_specialization_decision_is_recorded(helix::test::Reporter& reporter)
{
	using namespace helix::test::benchmark;

	const BenchmarkRecord record = sampleLegacySpinGlassRecord();
	const BenchmarkHypothesisEvidence* h001 = findEvidence(record, "H-001");
	reporter.expect(h001 != nullptr, "H-001 evidence exists for sparse backend decisions");
	if(h001 == nullptr)
	{
		return;
	}
	reporter.expect(evidenceFieldHasValue(*h001,
			"structured_v_specialization_decision",
			"defer_legacy_spin_glass_only"),
		"H-001 records the structured V specialization decision");
	reporter.expect(evidenceFieldHasValue(*h001,
			"structured_v_generic_sparse_contract",
			"unaffected:System::from_sparse_validation_only"),
		"H-001 records the generic sparse contract boundary");

	const std::string jsonl = toJsonLine(record);
	reporter.expect(jsonl.find("\"structured_v_specialization_decision\"") != std::string::npos,
		"JSONL includes structured V specialization decision evidence");
	reporter.expect(jsonl.find("\"structured_v_generic_sparse_contract\"") != std::string::npos,
		"JSONL includes generic sparse contract evidence");
}

void test_before_after_statistics_helpers(helix::test::Reporter& reporter)
{
	using namespace helix::test::benchmark;

	const BenchmarkMetricStats stats = summarizeBenchmarkSamples({10.0, 14.0, 12.0});
	reporter.expect(stats.count == 3, "sample statistics record sample count");
	reporter.expectNear(stats.minimum, 10.0, 1.0e-12, "sample statistics record minimum");
	reporter.expectNear(stats.maximum, 14.0, 1.0e-12, "sample statistics record maximum");
	reporter.expectNear(stats.median, 12.0, 1.0e-12, "sample statistics record median");
	reporter.expectNear(stats.sampleStddev, 2.0, 1.0e-12, "sample statistics record sample stdev");

	BenchmarkRecord record = sampleLegacySpinGlassRecord();
	record.problem.steadySteps = 5;
	record.problem.warmupSteps = 2;
	record.problem.steps = 7;
	record.timing.init = 1.0;
	record.timing.warmup = 2.0;
	record.timing.steadyPropagation = 25.0;
	record.timing.resultExtraction = 3.0;
	record.timing.teardown = 4.0;
	reporter.expectNear(steadyPropagationMsPerStep(record), 5.0, 1.0e-12,
		"steady propagation per-step metric divides by steady steps");
	reporter.expectNear(benchmarkMainTotalMs(record.timing), 35.0, 1.0e-12,
		"benchmark main total sums measured phases");

	reporter.expect(classifyBenchmarkPostPreRatio(0.90, 0.02, true)
			== BenchmarkBeforeAfterConclusion::OverallImproved,
		"ratio below one outside noise is an overall improvement");
	reporter.expect(classifyBenchmarkPostPreRatio(1.10, 0.02, true)
			== BenchmarkBeforeAfterConclusion::OverallRegressed,
		"ratio above one outside noise is an overall regression");
	reporter.expect(classifyBenchmarkPostPreRatio(1.01, 0.02, true)
			== BenchmarkBeforeAfterConclusion::WithinNoise,
		"ratio inside the noise band is within noise");
	reporter.expect(classifyBenchmarkPostPreRatio(0.90, 0.12, true)
			== BenchmarkBeforeAfterConclusion::InconclusiveDueToVarianceOrBuildMismatch,
		"high relative noise makes the conclusion inconclusive");
	reporter.expect(classifyBenchmarkPostPreRatio(0.90, 0.02, false)
			== BenchmarkBeforeAfterConclusion::InconclusiveDueToVarianceOrBuildMismatch,
		"build mismatch makes the conclusion inconclusive");
	reporter.expect(std::string(toString(BenchmarkBeforeAfterConclusion::OverallImproved))
			== "overall_improved",
		"before/after conclusion string is release-snippet friendly");
}

void test_jsonl_emission_contains_required_blocks_and_escapes_strings(helix::test::Reporter& reporter)
{
	auto record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.notes = "quoted \"note\" and newline\nmarker";

	const std::string jsonl = helix::test::benchmark::toJsonLine(record);

	reporter.expect(jsonl.find("\"schema_version\":\"helix.benchmark.v1\"") != std::string::npos,
		"JSONL includes schema_version");
	reporter.expect(jsonl.find("\"helix\":{") != std::string::npos, "JSONL includes helix block");
	reporter.expect(jsonl.find("\"build\":{") != std::string::npos, "JSONL includes build block");
	reporter.expect(jsonl.find("\"host\":{") != std::string::npos, "JSONL includes host block");
	reporter.expect(jsonl.find("\"gpu\":{") != std::string::npos, "JSONL includes gpu block");
	reporter.expect(jsonl.find("\"cuda\":{") != std::string::npos, "JSONL includes cuda block");
	reporter.expect(jsonl.find("\"case\":{") != std::string::npos, "JSONL includes case block");
	reporter.expect(jsonl.find("\"problem\":{") != std::string::npos, "JSONL includes problem block");
	reporter.expect(jsonl.find("\"timing_ms\":{") != std::string::npos, "JSONL includes timing_ms block");
	reporter.expect(jsonl.find("\"measurement_scope\":{") != std::string::npos,
		"JSONL includes measurement_scope block");
	reporter.expect(jsonl.find("\"main_measurement_scope\":\"benchmark.main\"") != std::string::npos,
		"JSONL states the main measurement scope");
	reporter.expect(jsonl.find("\"calibration_scope\":\"benchmark.calibration\"") != std::string::npos,
		"JSONL states the calibration scope");
	reporter.expect(jsonl.find("\"calibration_captured\":true") != std::string::npos,
		"JSONL states calibration capture state");
	reporter.expect(jsonl.find("\"calibration_excluded_from_main\":true") != std::string::npos,
		"JSONL states calibration exclusion from main aggregation");
	reporter.expect(jsonl.find("\"nvtx_naming_convention\":\"benchmark.main") != std::string::npos,
		"JSONL states the NVTX scope naming convention");
	reporter.expect(jsonl.find("\"memory\":{") != std::string::npos, "JSONL includes memory block");
	reporter.expect(jsonl.find("\"diagnostics\":{") != std::string::npos, "JSONL includes diagnostics block");
	reporter.expect(jsonl.find("\"gates\":{") != std::string::npos, "JSONL includes gates block");
	reporter.expect(jsonl.find("\"profiling\":{") != std::string::npos, "JSONL includes profiling block");
	reporter.expect(jsonl.find("\"counters\":{") != std::string::npos, "JSONL includes profiling counters");
	reporter.expect(jsonl.find("\"spmm\":{\"call_count\":\"not_collected\"") != std::string::npos,
		"JSONL emits not_collected SpMM counters");
	reporter.expect(jsonl.find("\"result_extraction\":{") != std::string::npos,
		"JSONL includes result extraction counters");
	reporter.expect(jsonl.find("\"sync_wait_ms\":") != std::string::npos,
		"JSONL includes result extraction sync wait");
	reporter.expect(jsonl.find("\"host_allocation_ms\":") != std::string::npos,
		"JSONL includes result extraction host allocation timing");
	reporter.expect(jsonl.find("\"d2h_copy_ms\":") != std::string::npos,
		"JSONL includes result extraction D2H copy timing");
	reporter.expect(jsonl.find("\"conversion_ms\":") != std::string::npos,
		"JSONL includes result extraction conversion timing");
	reporter.expect(jsonl.find("\"d2h_bytes\":") != std::string::npos,
		"JSONL includes result extraction D2H bytes");
	reporter.expect(jsonl.find("\"element_count\":") != std::string::npos,
		"JSONL includes result extraction element count");
	reporter.expect(jsonl.find("\"nsight_artifact\":null") != std::string::npos,
		"JSONL emits null nsight_artifact when capture is absent");
	record.profiling.nsightArtifact = "nsight/sample-systems.nsys-rep";
	const std::string jsonlWithNsight = helix::test::benchmark::toJsonLine(record);
	reporter.expect(jsonlWithNsight.find("\"nsight_artifact\":\"nsight/sample-systems.nsys-rep\"") != std::string::npos,
		"JSONL emits Nsight artifact path when capture is declared");
	reporter.expect(helix::test::benchmark::nsightArtifactSummaryValue(record.profiling.nsightArtifact)
			== "nsight/sample-systems.nsys-rep",
		"summary value reports declared Nsight artifact path");
	reporter.expect(jsonl.find("\"hypotheses\":[{") != std::string::npos,
		"JSONL emits structured profiling hypotheses");
	reporter.expect(jsonl.find("\"id\":\"H-001\"") != std::string::npos, "JSONL includes H-001 evidence");
	reporter.expect(jsonl.find("\"id\":\"H-005\"") != std::string::npos, "JSONL includes H-005 evidence");
	reporter.expect(jsonl.find("\"fields\":[{") != std::string::npos, "JSONL includes evidence fields");
	reporter.expect(jsonl.find("\"sync_audit_sites\"") != std::string::npos,
		"JSONL includes synchronization audit evidence");
	reporter.expect(jsonl.find("\"cuda_graph_decision\"") != std::string::npos,
		"JSONL includes CUDA Graph feasibility decision evidence");
	reporter.expect(jsonl.find("\"method\":") != std::string::npos, "JSONL includes evidence method");
	reporter.expect(jsonl.find("\"interpretation\":") != std::string::npos,
		"JSONL includes evidence interpretation");
	reporter.expect(jsonl.find("\"downstream_action\":") != std::string::npos,
		"JSONL includes evidence downstream action");
	reporter.expect(jsonl.find("\"steady_propagation_scope\":\"excludes_init_warmup_result_extraction\"")
			!= std::string::npos,
		"JSONL states steady propagation timing scope");
	reporter.expect(jsonl.find("\\\"note\\\"") != std::string::npos, "JSONL escapes quotes in string fields");
	reporter.expect(jsonl.find("\\nmarker") != std::string::npos, "JSONL escapes newlines in string fields");
	reporter.expect(!jsonl.empty() && jsonl.back() == '\n', "JSONL emission produces one newline-terminated line");
}

void test_negative_samples_report_field_paths(helix::test::Reporter& reporter)
{
	auto record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.schemaVersion.clear();
	expectInvalidPath(reporter, record, "schema_version", "missing schema version is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.caseInfo.backend = "UnknownBackend";
	expectInvalidPath(reporter, record, "case.backend", "unknown backend is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.timing.steadyPropagation = -0.01;
	expectInvalidPath(reporter, record, "timing_ms.steady_propagation", "negative steady timing is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.measurementScopes.mainMeasurementScope.clear();
	expectInvalidPath(reporter, record, "measurement_scope.main_measurement_scope",
		"missing main measurement scope is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.measurementScopes.calibrationStatus = "pending";
	expectInvalidPath(reporter, record, "measurement_scope.calibration_status",
		"invalid calibration status is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.measurementScopes.calibrationCaptured = false;
	expectInvalidPath(reporter, record, "measurement_scope.calibration_captured",
		"calibration capture flag must match captured status");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.measurementScopes.calibrationExcludedFromMain = false;
	expectInvalidPath(reporter, record, "measurement_scope.calibration_excluded_from_main",
		"calibration must be excluded from main aggregation");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.diagnostics.reset();
	expectInvalidPath(reporter, record, "diagnostics", "missing diagnostics mirror is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.memory.measurementMethod = "unsupported";
	expectInvalidPath(reporter, record, "memory.measurement_method", "invalid memory method is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.gates.correctnessGateStatus = "unknown";
	expectInvalidPath(reporter, record, "gates.correctness_gate_status", "invalid correctness gate status is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.gates.baselineGateStatus = "unknown";
	expectInvalidPath(reporter, record, "gates.baseline_gate_status", "invalid baseline gate status is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.profiling.hypotheses.front().status = "pending";
	expectInvalidPath(reporter, record, "profiling.hypotheses[0].status", "invalid evidence status is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.profiling.hypotheses.front().fields.clear();
	expectInvalidPath(reporter, record, "profiling.hypotheses[0].fields", "missing evidence fields are rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.profiling.hypotheses.pop_back();
	expectInvalidPath(reporter, record, "profiling.hypotheses.H-005", "missing H-005 slot is rejected");

	record = helix::test::benchmark::sampleLegacySpinGlassRecord();
	record.profiling.counters.resultExtraction.syncWaitMs =
		helix::test::benchmark::collectedCounter(-0.01, "ms");
	expectInvalidPath(reporter,
		record,
		"profiling.counters.result_extraction.sync_wait_ms",
		"negative result extraction sync wait counter is rejected");
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_enum_strings_match_public_api(reporter);
	test_sample_record_covers_contract(reporter);
	test_transpose_counters_promote_layout_evidence(reporter);
	test_sync_audit_evidence_records_graph_decision(reporter);
	test_structured_v_specialization_decision_is_recorded(reporter);
	test_before_after_statistics_helpers(reporter);
	test_jsonl_emission_contains_required_blocks_and_escapes_strings(reporter);
	test_negative_samples_report_field_paths(reporter);

	return reporter.finish("benchmark_schema_validation_tests");
}
