#include <helix/helix.h>

#include <pybind11/complex.h>
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <utility>

namespace py = pybind11;

namespace {

template <typename Enum>
void exposeEnumValueAliases(py::enum_<Enum>& binding)
{
	binding.export_values();
}

} // namespace

PYBIND11_MODULE(helix, module)
{
	module.doc() = "Experimental thin Python bindings for the HELIX public C++ API.";
	module.attr("__version__") = helix::versionString();
	module.def("runtime_version", &helix::runtimeVersion);

	auto backend = py::enum_<helix::Backend>(module, "Backend")
		.value("LegacyCudaSparse", helix::Backend::LegacyCudaSparse)
		.value("CudaSparse", helix::Backend::CudaSparse)
		.value("CpuReference", helix::Backend::CpuReference);
	exposeEnumValueAliases(backend);

	auto precision = py::enum_<helix::Precision>(module, "Precision")
		.value("Single", helix::Precision::Single)
		.value("Double", helix::Precision::Double);
	exposeEnumValueAliases(precision);

	auto systemKind = py::enum_<helix::SystemKind>(module, "SystemKind")
		.value("Sparse", helix::SystemKind::Sparse)
		.value("Dense", helix::SystemKind::Dense)
		.value("LegacySpinGlass", helix::SystemKind::LegacySpinGlass);
	exposeEnumValueAliases(systemKind);

	auto resultMode = py::enum_<helix::ResultMode>(module, "ResultMode")
		.value("FinalState", helix::ResultMode::FinalState)
		.value("ObservableTrace", helix::ResultMode::ObservableTrace)
		.value("Trajectory", helix::ResultMode::Trajectory);
	exposeEnumValueAliases(resultMode);

	auto storageOrder = py::enum_<helix::MatrixStorageOrder>(module, "MatrixStorageOrder")
		.value("RowMajor", helix::MatrixStorageOrder::RowMajor);
	exposeEnumValueAliases(storageOrder);

	auto runStatus = py::enum_<helix::RunStatus>(module, "RunStatus")
		.value("NotStarted", helix::RunStatus::NotStarted)
		.value("Success", helix::RunStatus::Success)
		.value("Failed", helix::RunStatus::Failed);
	exposeEnumValueAliases(runStatus);

	auto statusCode = py::enum_<helix::StatusCode>(module, "StatusCode")
		.value("InvalidDimension", helix::StatusCode::InvalidDimension)
		.value("InvalidRowOffsets", helix::StatusCode::InvalidRowOffsets)
		.value("InvalidColumnValueSize", helix::StatusCode::InvalidColumnValueSize)
		.value("InvalidColumnIndex", helix::StatusCode::InvalidColumnIndex)
		.value("InvalidCouplingDimension", helix::StatusCode::InvalidCouplingDimension)
		.value("InvalidRuntimeOption", helix::StatusCode::InvalidRuntimeOption)
		.value("UnsupportedPrecision", helix::StatusCode::UnsupportedPrecision)
		.value("UnsupportedBackend", helix::StatusCode::UnsupportedBackend)
		.value("UnsupportedSystemKind", helix::StatusCode::UnsupportedSystemKind)
		.value("UnsupportedExecution", helix::StatusCode::UnsupportedExecution)
		.value("UnsupportedBath", helix::StatusCode::UnsupportedBath)
		.value("UnsupportedHierarchy", helix::StatusCode::UnsupportedHierarchy)
		.value("ConcurrentContextUnsupported", helix::StatusCode::ConcurrentContextUnsupported);
	exposeEnumValueAliases(statusCode);

	py::class_<helix::Diagnostic>(module, "Diagnostic")
		.def_readwrite("code", &helix::Diagnostic::code)
		.def_readwrite("message", &helix::Diagnostic::message);

	py::class_<helix::Diagnostics>(module, "Diagnostics")
		.def(py::init<>())
		.def_readwrite("backend", &helix::Diagnostics::backend)
		.def_readwrite("precision", &helix::Diagnostics::precision)
		.def_readwrite("hilbertSize", &helix::Diagnostics::hilbertSize)
		.def_readwrite("hierarchySize", &helix::Diagnostics::hierarchySize)
		.def_readwrite("steps", &helix::Diagnostics::steps)
		.def_readwrite("timeStep", &helix::Diagnostics::timeStep)
		.def_readwrite("integrationOrder", &helix::Diagnostics::integrationOrder)
		.def_readwrite("status", &helix::Diagnostics::status)
		.def_readwrite("warnings", &helix::Diagnostics::warnings)
		.def("add", &helix::Diagnostics::add)
		.def("ok", &helix::Diagnostics::ok)
		.def("hasError", &helix::Diagnostics::hasError)
		.def("message", &helix::Diagnostics::message)
		.def("summary", &helix::Diagnostics::summary)
		.def_property_readonly("entries",
			[](const helix::Diagnostics& diagnostics) -> const std::vector<helix::Diagnostic>& {
				return diagnostics.entries();
			},
			py::return_value_policy::reference_internal);

	py::class_<helix::ContextOptions>(module, "ContextOptions")
		.def(py::init<>())
		.def_readwrite("backend", &helix::ContextOptions::backend)
		.def_readwrite("precision", &helix::ContextOptions::precision)
		.def_readwrite("allowConcurrentContexts", &helix::ContextOptions::allowConcurrentContexts)
		.def_readwrite("device", &helix::ContextOptions::device)
		.def_readwrite("integrationOrder", &helix::ContextOptions::integrationOrder)
		.def_readwrite("timeStep", &helix::ContextOptions::timeStep);

	py::class_<helix::SparseOperator>(module, "SparseOperator")
		.def(py::init<>())
		.def_readwrite("rows", &helix::SparseOperator::rows)
		.def_readwrite("cols", &helix::SparseOperator::cols)
		.def_readwrite("rowOffsets", &helix::SparseOperator::rowOffsets)
		.def_readwrite("columnIndices", &helix::SparseOperator::columnIndices)
		.def_readwrite("values", &helix::SparseOperator::values);

	py::class_<helix::Bath>(module, "Bath")
		.def(py::init<>())
		.def_readwrite("inverseTemperature", &helix::Bath::inverseTemperature)
		.def_readwrite("damping", &helix::Bath::damping)
		.def_readwrite("couplingStrength", &helix::Bath::couplingStrength)
		.def_readwrite("padeTerms", &helix::Bath::padeTerms)
		.def_readwrite("residues", &helix::Bath::residues)
		.def_readwrite("frequencies", &helix::Bath::frequencies)
		.def_static("drude_lorentz_pade", &helix::Bath::drude_lorentz_pade)
		.def("validate_supported", &helix::Bath::validate_supported);

	py::class_<helix::HierarchySpec>(module, "HierarchySpec")
		.def(py::init<>())
		.def_readwrite("maxDepth", &helix::HierarchySpec::maxDepth)
		.def_readwrite("exponentialTerms", &helix::HierarchySpec::exponentialTerms)
		.def_readwrite("baths", &helix::HierarchySpec::baths)
		.def_static("compiled_default",
			[](helix::Bath bath) {
				return helix::HierarchySpec::compiled_default(std::move(bath));
			},
			py::arg("bath") = helix::Bath::drude_lorentz_pade())
		.def("validate_supported", &helix::HierarchySpec::validate_supported);

	py::class_<helix::SolverOptions>(module, "SolverOptions")
		.def(py::init<>())
		.def_readwrite("steps", &helix::SolverOptions::steps)
		.def_readwrite("timeStep", &helix::SolverOptions::timeStep)
		.def_readwrite("resultMode", &helix::SolverOptions::resultMode);

	py::class_<helix::System>(module, "System")
		.def(py::init<>())
		.def_readwrite("kind", &helix::System::kind)
		.def_readwrite("hamiltonian", &helix::System::hamiltonian)
		.def_readwrite("couplings", &helix::System::couplings)
		.def_readwrite("diagnostics", &helix::System::diagnostics)
		.def("valid", &helix::System::valid)
		.def_static("from_sparse",
			&helix::System::from_sparse,
			py::arg("hamiltonian"),
			py::arg("couplings") = std::vector<helix::SparseOperator>{});

	py::class_<helix::ReducedDensityShape>(module, "ReducedDensityShape")
		.def(py::init<>())
		.def_readwrite("count", &helix::ReducedDensityShape::count)
		.def_readwrite("rows", &helix::ReducedDensityShape::rows)
		.def_readwrite("cols", &helix::ReducedDensityShape::cols)
		.def_readwrite("storageOrder", &helix::ReducedDensityShape::storageOrder);

	py::class_<helix::RunResult>(module, "RunResult")
		.def(py::init<>())
		.def_readwrite("times", &helix::RunResult::times)
		.def_readwrite("reduced_density", &helix::RunResult::reduced_density)
		.def_readwrite("reduced_density_shape", &helix::RunResult::reduced_density_shape)
		.def_readwrite("diagnostics", &helix::RunResult::diagnostics)
		.def("ok", &helix::RunResult::ok);

	py::class_<helix::Context>(module, "Context")
		.def(py::init<helix::ContextOptions>(), py::arg("options") = helix::ContextOptions{})
		.def("diagnostics", &helix::Context::diagnostics, py::return_value_policy::reference_internal)
		.def("active", &helix::Context::active)
		.def("run_steps", &helix::Context::run_steps)
		.def("reduced_density", &helix::Context::reduced_density)
		.def("destroy", &helix::Context::destroy);

	py::class_<helix::HEOMSolver>(module, "HEOMSolver")
		.def(py::init<>())
		.def(py::init<helix::ContextOptions>(), py::arg("options"))
		.def(py::init<helix::Context&, helix::System, helix::Bath, helix::HierarchySpec, helix::SolverOptions>(),
			py::keep_alive<1, 2>(),
			py::arg("context"),
			py::arg("system"),
			py::arg("bath"),
			py::arg("hierarchy"),
			py::arg("options") = helix::SolverOptions{})
		.def("validate_options", &helix::HEOMSolver::validate_options)
		.def("run_steps", &helix::HEOMSolver::run_steps)
		.def("run", &helix::HEOMSolver::run);

	auto examples = module.def_submodule("examples", "Compatibility example constructors.");
	examples.def("legacy_spin_glass_system", &helix::examples::legacy_spin_glass_system);
}
