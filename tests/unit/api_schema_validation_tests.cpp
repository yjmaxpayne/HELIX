#include <helix/helix.h>
#include <helix/examples.h>

#include "support/assert.h"
#include <string>
#include <vector>

namespace {

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

void expectDiagnostic(helix::test::Reporter& reporter,
	const helix::Diagnostics& diagnostics,
	helix::StatusCode code,
	const char* message)
{
	reporter.expect(diagnostics.hasError(code), message);
	reporter.expect(!diagnostics.message(code).empty(), std::string(message) + " has explanatory message");
}

void test_valid_sparse_system_is_validation_clean(helix::test::Reporter& reporter)
{
	auto system = helix::System::from_sparse(validOperator(2), {});
	reporter.expect(system.valid(), "valid sparse system passes schema validation");
	reporter.expect(system.kind == helix::SystemKind::Sparse, "valid sparse system reports sparse kind");
	reporter.expect(system.diagnostics.ok(), "valid sparse system diagnostics are clean");
}

void test_rejects_non_square_system_operator(helix::test::Reporter& reporter)
{
	auto op = validOperator(2);
	op.cols = 3;

	auto system = helix::System::from_sparse(op, {});

	reporter.expect(!system.valid(), "non-square system operator is invalid");
	expectDiagnostic(reporter, system.diagnostics, helix::StatusCode::InvalidDimension, "non-square system diagnostic");
}

void test_rejects_row_offset_size_mismatch(helix::test::Reporter& reporter)
{
	auto op = validOperator(2);
	op.rowOffsets.pop_back();

	auto system = helix::System::from_sparse(op, {});

	reporter.expect(!system.valid(), "row offset size mismatch is invalid");
	expectDiagnostic(reporter, system.diagnostics, helix::StatusCode::InvalidRowOffsets, "row offset size diagnostic");
}

void test_rejects_column_value_size_mismatch(helix::test::Reporter& reporter)
{
	auto op = validOperator(2);
	op.values.pop_back();

	auto system = helix::System::from_sparse(op, {});

	reporter.expect(!system.valid(), "column/value size mismatch is invalid");
	expectDiagnostic(reporter, system.diagnostics, helix::StatusCode::InvalidColumnValueSize, "column/value size diagnostic");
}

void test_rejects_non_monotonic_row_offsets(helix::test::Reporter& reporter)
{
	auto op = validOperator(2);
	op.rowOffsets = {0, 2, 1};

	auto system = helix::System::from_sparse(op, {});

	reporter.expect(!system.valid(), "non-monotonic row offsets are invalid");
	expectDiagnostic(reporter, system.diagnostics, helix::StatusCode::InvalidRowOffsets, "monotonic row offset diagnostic");
}

void test_rejects_coupling_dimension_mismatch(helix::test::Reporter& reporter)
{
	auto system = helix::System::from_sparse(validOperator(2), {validOperator(3)});

	reporter.expect(!system.valid(), "coupling dimension mismatch is invalid");
	expectDiagnostic(reporter,
		system.diagnostics,
		helix::StatusCode::InvalidCouplingDimension,
		"coupling dimension diagnostic");
}

void test_reports_unsupported_precision_backend_and_context(helix::test::Reporter& reporter)
{
	helix::ContextOptions options;
	options.precision = helix::Precision::Double;
	options.backend = helix::Backend::CpuReference;
	options.allowConcurrentContexts = true;

	auto diagnostics = helix::HEOMSolver(options).validate_options();

	expectDiagnostic(reporter, diagnostics, helix::StatusCode::UnsupportedPrecision, "unsupported precision diagnostic");
	expectDiagnostic(reporter, diagnostics, helix::StatusCode::UnsupportedBackend, "unsupported backend diagnostic");
	expectDiagnostic(reporter,
		diagnostics,
		helix::StatusCode::ConcurrentContextUnsupported,
		"unsupported concurrent context diagnostic");
}

void test_default_bath_and_hierarchy_are_supported(helix::test::Reporter& reporter)
{
	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);

	reporter.expect(bath.validate_supported().ok(), "compiled Drude-Lorentz Pade bath is supported");
	reporter.expect(hierarchy.validate_supported().ok(), "compiled hierarchy mapping is supported");

	auto system = helix::examples::legacy_spin_glass_system();
	reporter.expect(system.valid(), "legacy spin-glass example adapter is validation clean");
	reporter.expect(system.kind == helix::SystemKind::LegacySpinGlass,
		"legacy spin-glass example adapter reports the compatibility system kind");
}

void test_rejects_non_default_bath_fields(helix::test::Reporter& reporter)
{
	auto bath = helix::Bath::drude_lorentz_pade();
	bath.damping = 2.0;

	const auto diagnostics = bath.validate_supported();

	reporter.expect(!diagnostics.ok(), "non-default bath damping is constrained in v0.1");
	expectDiagnostic(reporter,
		diagnostics,
		helix::StatusCode::UnsupportedBath,
		"unsupported bath diagnostic");
}

void test_rejects_non_default_hierarchy_fields(helix::test::Reporter& reporter)
{
	auto hierarchy = helix::HierarchySpec::compiled_default();
	hierarchy.maxDepth += 1;

	const auto diagnostics = hierarchy.validate_supported();

	reporter.expect(!diagnostics.ok(), "non-default hierarchy depth is constrained in v0.1");
	expectDiagnostic(reporter,
		diagnostics,
		helix::StatusCode::UnsupportedHierarchy,
		"unsupported hierarchy diagnostic");
}

void test_reports_sparse_execution_as_validation_only(helix::test::Reporter& reporter)
{
	auto system = helix::System::from_sparse(validOperator(2), {});
	auto result = helix::HEOMSolver().run(system, helix::HierarchySpec{}, helix::SolverOptions{});

	reporter.expect(!result.diagnostics.ok(), "arbitrary sparse execution is unsupported in v0.1");
	expectDiagnostic(reporter,
		result.diagnostics,
		helix::StatusCode::UnsupportedExecution,
		"validation-only execution diagnostic");
	reporter.expect(result.diagnostics.message(helix::StatusCode::UnsupportedExecution).find("validation-only")
			!= std::string::npos,
		"unsupported execution message says validation-only");
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_valid_sparse_system_is_validation_clean(reporter);
	test_rejects_non_square_system_operator(reporter);
	test_rejects_row_offset_size_mismatch(reporter);
	test_rejects_column_value_size_mismatch(reporter);
	test_rejects_non_monotonic_row_offsets(reporter);
	test_rejects_coupling_dimension_mismatch(reporter);
	test_reports_unsupported_precision_backend_and_context(reporter);
	test_default_bath_and_hierarchy_are_supported(reporter);
	test_rejects_non_default_bath_fields(reporter);
	test_rejects_non_default_hierarchy_fields(reporter);
	test_reports_sparse_execution_as_validation_only(reporter);

	return reporter.finish("api_schema_validation_tests");
}
