#include <helix/types.h>
#include <helix/version.h>

#include "library/legacy_runtime_session.h"
#include "library/result_extractor.h"
#include "parameters.h"

#include <algorithm>
#include <atomic>
#include <cuda_runtime.h>
#include <cmath>
#include <stdexcept>
#include <sstream>
#include <utility>

namespace helix {

const char* runtimeVersion() noexcept
{
	return versionString();
}

void Diagnostics::add(StatusCode code, std::string message)
{
	entries_.push_back({code, std::move(message)});
	status = RunStatus::Failed;
}

bool Diagnostics::ok() const noexcept
{
	return entries_.empty();
}

bool Diagnostics::hasError(StatusCode code) const noexcept
{
	return std::any_of(entries_.begin(), entries_.end(), [code](const Diagnostic& diagnostic) {
		return diagnostic.code == code;
	});
}

std::string Diagnostics::message(StatusCode code) const
{
	const auto it = std::find_if(entries_.begin(), entries_.end(), [code](const Diagnostic& diagnostic) {
		return diagnostic.code == code;
	});
	return it == entries_.end() ? std::string{} : it->message;
}

std::string Diagnostics::summary() const
{
	std::ostringstream output;
	for(std::size_t i = 0; i < entries_.size(); ++i)
	{
		if(i != 0)
		{
			output << "; ";
		}
		output << entries_[i].message;
	}
	return output.str();
}

const std::vector<Diagnostic>& Diagnostics::entries() const noexcept
{
	return entries_;
}

namespace {

constexpr const char* kSequentialLifecycleMessage =
	"HELIX v0.1 supports only sequential lifecycle: one active Context may own the legacy runtime session";

std::atomic_bool& activeContextFlag()
{
	static std::atomic_bool value{false};
	return value;
}

class ActiveContextLease {
public:
	ActiveContextLease()
	{
		bool expected = false;
		if(!activeContextFlag().compare_exchange_strong(expected, true))
		{
			throw std::logic_error(kSequentialLifecycleMessage);
		}
		owns_ = true;
	}

	~ActiveContextLease() noexcept
	{
		if(owns_)
		{
			activeContextFlag().store(false);
		}
	}

	ActiveContextLease(const ActiveContextLease&) = delete;
	ActiveContextLease& operator=(const ActiveContextLease&) = delete;

private:
	bool owns_ = false;
};

void addOperatorContext(Diagnostics& diagnostics,
	StatusCode code,
	const char* name,
	const std::string& message)
{
	diagnostics.add(code, std::string(name) + ": " + message);
}

bool nearDefault(double actual, double expected)
{
	return std::abs(actual - expected) <= 1.0e-12;
}

bool nearDefault(const std::complex<double>& actual, const std::complex<double>& expected)
{
	return nearDefault(actual.real(), expected.real()) && nearDefault(actual.imag(), expected.imag());
}

bool vectorNearDefault(const std::vector<double>& actual, const std::vector<double>& expected)
{
	if(actual.size() != expected.size())
	{
		return false;
	}
	for(std::size_t i = 0; i < actual.size(); ++i)
	{
		if(!nearDefault(actual[i], expected[i]))
		{
			return false;
		}
	}
	return true;
}

bool vectorNearDefault(
	const std::vector<std::complex<double>>& actual,
	const std::vector<std::complex<double>>& expected)
{
	if(actual.size() != expected.size())
	{
		return false;
	}
	for(std::size_t i = 0; i < actual.size(); ++i)
	{
		if(!nearDefault(actual[i], expected[i]))
		{
			return false;
		}
	}
	return true;
}

void appendDiagnostics(Diagnostics& target, const Diagnostics& source)
{
	for(const auto& diagnostic : source.entries())
	{
		target.add(diagnostic.code, diagnostic.message);
	}
}

class SystemValidator {
public:
	Diagnostics validate(const SparseOperator& hamiltonian, const std::vector<SparseOperator>& couplings) const
	{
		Diagnostics diagnostics;
		validateOperator("hamiltonian", hamiltonian, diagnostics);

		if(hamiltonian.rows != hamiltonian.cols)
		{
			addOperatorContext(diagnostics,
				StatusCode::InvalidDimension,
				"hamiltonian",
				"system operator must be square");
		}

		for(std::size_t i = 0; i < couplings.size(); ++i)
		{
			const auto& coupling = couplings[i];
			const auto name = "coupling[" + std::to_string(i) + "]";
			validateOperator(name.c_str(), coupling, diagnostics);
			if(coupling.rows != hamiltonian.rows || coupling.cols != hamiltonian.cols)
			{
				addOperatorContext(diagnostics,
					StatusCode::InvalidCouplingDimension,
					name.c_str(),
					"coupling operator dimensions must match the system operator");
			}
		}

		return diagnostics;
	}

private:
	void validateOperator(const char* name, const SparseOperator& op, Diagnostics& diagnostics) const
	{
		if(op.rowOffsets.size() != op.rows + 1)
		{
			addOperatorContext(diagnostics,
				StatusCode::InvalidRowOffsets,
				name,
				"CSR rowOffsets size must equal rows + 1");
			return;
		}

		if(op.rowOffsets.empty() || op.rowOffsets.front() != 0)
		{
			addOperatorContext(diagnostics,
				StatusCode::InvalidRowOffsets,
				name,
				"CSR rowOffsets must start at zero");
		}

		for(std::size_t i = 1; i < op.rowOffsets.size(); ++i)
		{
			if(op.rowOffsets[i] < op.rowOffsets[i - 1])
			{
				addOperatorContext(diagnostics,
					StatusCode::InvalidRowOffsets,
					name,
					"CSR rowOffsets must be monotonically nondecreasing");
				break;
			}
		}

		if(op.columnIndices.size() != op.values.size())
		{
			addOperatorContext(diagnostics,
				StatusCode::InvalidColumnValueSize,
				name,
				"CSR columnIndices and values must have identical sizes");
		}

		if(!op.rowOffsets.empty() && op.rowOffsets.back() != op.columnIndices.size())
		{
			addOperatorContext(diagnostics,
				StatusCode::InvalidRowOffsets,
				name,
				"CSR final row offset must equal the number of column entries");
		}

		for(const auto column : op.columnIndices)
		{
			if(column >= op.cols)
			{
				addOperatorContext(diagnostics,
					StatusCode::InvalidColumnIndex,
					name,
					"CSR column index is outside operator dimensions");
				break;
			}
		}
	}
};

Diagnostics validateContextOptions(const ContextOptions& options)
{
	Diagnostics diagnostics;

	if(options.precision != Precision::Single)
	{
		diagnostics.add(StatusCode::UnsupportedPrecision,
			"HELIX v0.1 supports only single precision through the legacy CUDA sparse runtime");
	}

	if(options.backend != Backend::LegacyCudaSparse)
	{
		diagnostics.add(StatusCode::UnsupportedBackend,
			"HELIX v0.1 supports only Backend::LegacyCudaSparse for runtime execution");
	}

	if(options.allowConcurrentContexts)
	{
		diagnostics.add(StatusCode::ConcurrentContextUnsupported, kSequentialLifecycleMessage);
	}

	if(options.device < 0)
	{
		diagnostics.add(StatusCode::InvalidRuntimeOption, "CUDA device index must be non-negative");
	}

	if(options.integrationOrder <= 0)
	{
		diagnostics.add(StatusCode::InvalidRuntimeOption, "integrationOrder must be positive");
	}

	if(options.timeStep <= 0.0)
	{
		diagnostics.add(StatusCode::InvalidRuntimeOption, "timeStep must be positive");
	}

	return diagnostics;
}

library::LegacyRuntimeSessionConfig runtimeConfigFromOptions(const ContextOptions& options)
{
	library::LegacyRuntimeSessionConfig config;
	config.integrationOrder = options.integrationOrder;
	config.step = options.timeStep;
	return config;
}

Diagnostics validateSolverOptions(const SolverOptions& options)
{
	Diagnostics diagnostics;
	if(options.timeStep < 0.0)
	{
		diagnostics.add(StatusCode::InvalidRuntimeOption, "SolverOptions::timeStep must be non-negative");
	}

	if(options.resultMode != ResultMode::FinalState)
	{
		diagnostics.add(StatusCode::UnsupportedExecution,
			"HELIX v0.1 solver execution returns only the final reduced density state");
	}
	return diagnostics;
}

Diagnostics validateLegacyAdapterProblem(
	const System& system,
	const Bath& bath,
	const HierarchySpec& hierarchy,
	const SolverOptions& options)
{
	Diagnostics diagnostics;
	appendDiagnostics(diagnostics, system.diagnostics);
	appendDiagnostics(diagnostics, bath.validate_supported());
	appendDiagnostics(diagnostics, hierarchy.validate_supported());
	appendDiagnostics(diagnostics, validateSolverOptions(options));

	if(system.kind != SystemKind::LegacySpinGlass)
	{
		if(system.kind == SystemKind::Sparse)
		{
			diagnostics.add(StatusCode::UnsupportedExecution,
				"Arbitrary sparse HEOM execution is validation-only in HELIX v0.1; use helix::examples::legacy_spin_glass_system() for the legacy compatibility path");
		}
		else
		{
			diagnostics.add(StatusCode::UnsupportedSystemKind,
				"HELIX v0.1 runtime execution supports only the legacy spin-glass compatibility adapter");
		}
	}

	return diagnostics;
}

Precision runtimePrecision() noexcept
{
#ifdef SINGLE
	return Precision::Single;
#else
	return Precision::Double;
#endif
}

void populateSuccessfulRunDiagnostics(Diagnostics& diagnostics, std::size_t steps)
{
	diagnostics.backend = Backend::LegacyCudaSparse;
	diagnostics.precision = runtimePrecision();
	diagnostics.hilbertSize = static_cast<std::size_t>(Param::N);
	diagnostics.hierarchySize = library::ResultExtractor::hierarchy_size();
	diagnostics.steps = steps;
	diagnostics.timeStep = Param::Step;
	diagnostics.integrationOrder = Param::IntegrationNum;
	diagnostics.status = RunStatus::Success;
}

} // namespace

Bath Bath::drude_lorentz_pade()
{
	Bath bath;
	bath.inverseTemperature = Param::Betah;
	bath.damping = Param::Gamma;
	bath.couplingStrength = Param::Zeta;
	bath.padeTerms = static_cast<std::size_t>(Param::KMax);

	return bath;
}

Diagnostics Bath::validate_supported() const
{
	Diagnostics diagnostics;
	const Bath expected = Bath::drude_lorentz_pade();

	if(!nearDefault(inverseTemperature, expected.inverseTemperature))
	{
		diagnostics.add(StatusCode::UnsupportedBath,
			"HELIX v0.1 legacy runtime is constrained to the compiled inverse temperature");
	}

	if(!nearDefault(damping, expected.damping))
	{
		diagnostics.add(StatusCode::UnsupportedBath,
			"HELIX v0.1 legacy runtime is constrained to the compiled bath damping");
	}

	if(!nearDefault(couplingStrength, expected.couplingStrength))
	{
		diagnostics.add(StatusCode::UnsupportedBath,
			"HELIX v0.1 legacy runtime is constrained to the compiled bath coupling strength");
	}

	if(padeTerms != expected.padeTerms)
	{
		diagnostics.add(StatusCode::UnsupportedBath,
			"HELIX v0.1 legacy runtime is constrained to the compiled Pade term count");
	}

	if(!frequencies.empty() && !vectorNearDefault(frequencies, expected.frequencies))
	{
		diagnostics.add(StatusCode::UnsupportedBath,
			"HELIX v0.1 legacy runtime keeps bath frequencies behind the compiled adapter");
	}

	if(!residues.empty() && !vectorNearDefault(residues, expected.residues))
	{
		diagnostics.add(StatusCode::UnsupportedBath,
			"HELIX v0.1 legacy runtime keeps Pade residues behind the compiled adapter");
	}

	return diagnostics;
}

HierarchySpec HierarchySpec::compiled_default(Bath bath)
{
	HierarchySpec hierarchy;
	hierarchy.maxDepth = static_cast<std::size_t>(Param::JMax);
	hierarchy.exponentialTerms = static_cast<std::size_t>(Param::KMax + 1);
	hierarchy.baths.push_back(std::move(bath));
	return hierarchy;
}

Diagnostics HierarchySpec::validate_supported() const
{
	Diagnostics diagnostics;
	const HierarchySpec expected = HierarchySpec::compiled_default();

	if(maxDepth != expected.maxDepth)
	{
		diagnostics.add(StatusCode::UnsupportedHierarchy,
			"HELIX v0.1 legacy runtime is constrained to the compiled hierarchy depth");
	}

	if(exponentialTerms != expected.exponentialTerms)
	{
		diagnostics.add(StatusCode::UnsupportedHierarchy,
			"HELIX v0.1 legacy runtime is constrained to the compiled hierarchy exponential term count");
	}

	if(baths.size() != 1)
	{
		diagnostics.add(StatusCode::UnsupportedHierarchy,
			"HELIX v0.1 legacy runtime expects exactly one compiled Drude-Lorentz bath");
		return diagnostics;
	}

	for(const auto& diagnostic : baths.front().validate_supported().entries())
	{
		diagnostics.add(diagnostic.code, std::string("hierarchy bath: ") + diagnostic.message);
	}

	return diagnostics;
}

bool System::valid() const noexcept
{
	return diagnostics.ok();
}

System System::from_sparse(SparseOperator hamiltonian, std::vector<SparseOperator> couplings)
{
	System system;
	system.kind = SystemKind::Sparse;
	system.hamiltonian = std::move(hamiltonian);
	system.couplings = std::move(couplings);
	system.diagnostics = SystemValidator{}.validate(system.hamiltonian, system.couplings);
	return system;
}

namespace examples {

System legacy_spin_glass_system()
{
	System system;
	system.kind = SystemKind::LegacySpinGlass;
	return system;
}

} // namespace examples

bool RunResult::ok() const noexcept
{
	return diagnostics.ok();
}

class Context::Impl {
public:
	explicit Impl(ContextOptions options)
		: options_(options),
		  session_(runtimeConfigFromOptions(options))
	{
		diagnostics_ = validateContextOptions(options_);
		if(!diagnostics_.ok())
		{
			throw std::invalid_argument(diagnostics_.summary());
		}

		activeLease_ = std::make_unique<ActiveContextLease>();

		const cudaError_t deviceStatus = cudaSetDevice(options_.device);
		if(deviceStatus != cudaSuccess)
		{
			throw std::runtime_error(std::string("Failed to set HELIX CUDA device: ")
				+ cudaGetErrorString(deviceStatus));
		}

		session_.create();
	}

	~Impl() noexcept
	{
		destroy();
	}

	const Diagnostics& diagnostics() const noexcept
	{
		return diagnostics_;
	}

	bool active() const noexcept
	{
		return session_.active();
	}

	void run_steps(std::size_t steps)
	{
		session_.run_steps(steps);
	}

	std::vector<std::complex<double>> reduced_density() const
	{
		return session_.reduced_density();
	}

	void destroy() noexcept
	{
		session_.destroy();
		activeLease_.reset();
	}

private:
	ContextOptions options_;
	Diagnostics diagnostics_;
	std::unique_ptr<ActiveContextLease> activeLease_;
	library::LegacyRuntimeSession session_;
};

Context::Context(ContextOptions options)
	: impl_(std::make_unique<Impl>(options))
{
}

Context::~Context() noexcept = default;

Context::Context(Context&&) noexcept = default;

Context& Context::operator=(Context&&) noexcept = default;

const Diagnostics& Context::diagnostics() const noexcept
{
	static const Diagnostics emptyDiagnostics;
	return impl_ == nullptr ? emptyDiagnostics : impl_->diagnostics();
}

bool Context::active() const noexcept
{
	return impl_ != nullptr && impl_->active();
}

void Context::run_steps(std::size_t steps)
{
	if(impl_ == nullptr)
	{
		throw std::logic_error("Cannot run a moved-from HELIX Context");
	}
	impl_->run_steps(steps);
}

std::vector<std::complex<double>> Context::reduced_density() const
{
	if(impl_ == nullptr)
	{
		throw std::logic_error("Cannot read reduced density from a moved-from HELIX Context");
	}
	return impl_->reduced_density();
}

void Context::destroy() noexcept
{
	if(impl_ != nullptr)
	{
		impl_->destroy();
	}
}

HEOMSolver::HEOMSolver() = default;

HEOMSolver::HEOMSolver(ContextOptions options)
	: options_(options)
{
}

HEOMSolver::HEOMSolver(Context& context,
	System system,
	Bath bath,
	HierarchySpec hierarchy,
	SolverOptions options)
	: context_(&context),
	  system_(std::move(system)),
	  bath_(std::move(bath)),
	  hierarchy_(std::move(hierarchy)),
	  solverOptions_(options)
{
}

Diagnostics HEOMSolver::validate_options() const
{
	return validateContextOptions(options_);
}

RunResult HEOMSolver::run_steps(std::size_t steps)
{
	RunResult result;
	if(context_ == nullptr)
	{
		result.diagnostics.add(StatusCode::InvalidRuntimeOption,
			"HEOMSolver::run_steps requires a Context-bound solver");
		return result;
	}

	result.diagnostics = validateLegacyAdapterProblem(system_, bath_, hierarchy_, solverOptions_);
	if(!result.diagnostics.ok())
	{
		return result;
	}

	try
	{
		context_->run_steps(steps);
		auto extraction = library::ResultExtractor::final_reduced_density();
		result.reduced_density = std::move(extraction.values);
		result.reduced_density_shape = extraction.shape;
		const double stepSize = Param::Step;
		result.times.push_back(static_cast<double>(steps) * stepSize);
		populateSuccessfulRunDiagnostics(result.diagnostics, steps);
	}
	catch(const std::exception& error)
	{
		result.diagnostics.add(StatusCode::InvalidRuntimeOption, error.what());
	}

	return result;
}

RunResult HEOMSolver::run(const System& system, const HierarchySpec& hierarchy, const SolverOptions& options) const
{
	RunResult result;
	result.diagnostics = validate_options();

	appendDiagnostics(result.diagnostics, system.diagnostics);
	appendDiagnostics(result.diagnostics, hierarchy.validate_supported());
	appendDiagnostics(result.diagnostics, validateSolverOptions(options));

	if(system.kind != SystemKind::LegacySpinGlass)
	{
		if(system.kind == SystemKind::Sparse)
		{
			result.diagnostics.add(StatusCode::UnsupportedExecution,
				"Arbitrary sparse HEOM execution is validation-only in HELIX v0.1; use helix::examples::legacy_spin_glass_system() for the legacy compatibility path");
		}
		else
		{
			result.diagnostics.add(StatusCode::UnsupportedSystemKind,
				"HELIX v0.1 runtime execution supports only the legacy spin-glass compatibility adapter");
		}
		return result;
	}

	if(!result.diagnostics.ok())
	{
		return result;
	}

	try
	{
		ContextOptions contextOptions = options_;
		if(options.timeStep > 0.0)
		{
			contextOptions.timeStep = options.timeStep;
		}

		Context context(contextOptions);
		const Bath bath = hierarchy.baths.empty() ? Bath::drude_lorentz_pade() : hierarchy.baths.front();
		HEOMSolver boundSolver(context, system, bath, hierarchy, options);
		result = boundSolver.run_steps(options.steps);
		context.destroy();
	}
	catch(const std::exception& error)
	{
		result.diagnostics.add(StatusCode::InvalidRuntimeOption, error.what());
	}

	return result;
}

} // namespace helix
