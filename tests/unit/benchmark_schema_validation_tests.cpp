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
	reporter.expect(jsonl.find("\"memory\":{") != std::string::npos, "JSONL includes memory block");
	reporter.expect(jsonl.find("\"diagnostics\":{") != std::string::npos, "JSONL includes diagnostics block");
	reporter.expect(jsonl.find("\"gates\":{") != std::string::npos, "JSONL includes gates block");
	reporter.expect(jsonl.find("\"profiling\":{") != std::string::npos, "JSONL includes profiling block");
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
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_enum_strings_match_public_api(reporter);
	test_sample_record_covers_contract(reporter);
	test_jsonl_emission_contains_required_blocks_and_escapes_strings(reporter);
	test_negative_samples_report_field_paths(reporter);

	return reporter.finish("benchmark_schema_validation_tests");
}
