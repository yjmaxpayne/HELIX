#pragma once

#include <complex>
#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace helix {

enum class Backend {
	LegacyCudaSparse,
	CudaSparse,
	CpuReference
};

enum class Precision {
	Single,
	Double
};

enum class SystemKind {
	Sparse,
	Dense,
	LegacySpinGlass
};

enum class ResultMode {
	FinalState,
	ObservableTrace,
	Trajectory
};

enum class MatrixStorageOrder {
	// Public reduced_density buffers are row-major. Backend-local layout changes
	// must convert before publishing RunResult values.
	RowMajor
};

enum class RunStatus {
	NotStarted,
	Success,
	Failed
};

enum class StatusCode {
	InvalidDimension,
	InvalidRowOffsets,
	InvalidColumnValueSize,
	InvalidColumnIndex,
	InvalidCouplingDimension,
	InvalidRuntimeOption,
	UnsupportedPrecision,
	UnsupportedBackend,
	UnsupportedSystemKind,
	UnsupportedExecution,
	UnsupportedBath,
	UnsupportedHierarchy,
	ConcurrentContextUnsupported,
	BathExponentsInvalid
};

struct Diagnostic {
	StatusCode code;
	std::string message;
};

class Diagnostics {
public:
	Backend backend = Backend::LegacyCudaSparse;
	Precision precision = Precision::Single;
	std::size_t hilbertSize = 0;
	std::size_t hierarchySize = 0;
	std::size_t steps = 0;
	double timeStep = 0.0;
	int integrationOrder = 0;
	RunStatus status = RunStatus::NotStarted;
	std::vector<std::string> warnings;

	void add(StatusCode code, std::string message);
	bool ok() const noexcept;
	bool hasError(StatusCode code) const noexcept;
	std::string message(StatusCode code) const;
	std::string summary() const;
	const std::vector<Diagnostic>& entries() const noexcept;

private:
	std::vector<Diagnostic> entries_;
};

struct ContextOptions {
	Backend backend = Backend::LegacyCudaSparse;
	Precision precision = Precision::Single;
	bool allowConcurrentContexts = false;
	int device = 0;
	int integrationOrder = 4;
	double timeStep = 0.1;
};

struct SparseOperator {
	std::size_t rows = 0;
	std::size_t cols = 0;
	std::vector<std::size_t> rowOffsets;
	std::vector<std::size_t> columnIndices;
	std::vector<std::complex<double>> values;
};

struct Bath {
	enum class Kind {
		DrudeLorentzPade,
		UserExponents
	};

	Kind kind = Kind::DrudeLorentzPade;
	double inverseTemperature = 0.0;
	double damping = 0.0;
	double couplingStrength = 0.0;
	std::size_t padeTerms = 0;
	std::vector<std::complex<double>> residues;
	std::vector<double> frequencies;
	std::vector<std::complex<double>> exponentCoefficients;
	std::vector<std::complex<double>> exponentRates;

	static Bath drude_lorentz_pade();
	static Bath user_exponents(std::vector<std::complex<double>> coefficients,
		std::vector<std::complex<double>> rates);
	Diagnostics validate_supported() const;
};

struct HierarchySpec {
	std::size_t maxDepth = 0;
	std::size_t exponentialTerms = 0;
	std::vector<Bath> baths;

	static HierarchySpec compiled_default(Bath bath = Bath::drude_lorentz_pade());
	Diagnostics validate_supported() const;
};

struct SolverOptions {
	std::size_t steps = 0;
	double timeStep = 0.0;
	ResultMode resultMode = ResultMode::FinalState;
};

struct System {
	SystemKind kind = SystemKind::Sparse;
	SparseOperator hamiltonian;
	std::vector<SparseOperator> couplings;
	Diagnostics diagnostics;

	bool valid() const noexcept;
	static System from_sparse(SparseOperator hamiltonian, std::vector<SparseOperator> couplings = {});
};

struct ReducedDensityShape {
	std::size_t count = 0;
	std::size_t rows = 0;
	std::size_t cols = 0;
	MatrixStorageOrder storageOrder = MatrixStorageOrder::RowMajor;
};

struct RunResult {
	std::vector<double> times;
	std::vector<std::complex<double>> reduced_density;
	ReducedDensityShape reduced_density_shape;
	Diagnostics diagnostics;

	bool ok() const noexcept;
};

class Context {
public:
	explicit Context(ContextOptions options = {});
	~Context() noexcept;

	Context(const Context&) = delete;
	Context& operator=(const Context&) = delete;
	Context(Context&&) noexcept;
	Context& operator=(Context&&) noexcept;

	const Diagnostics& diagnostics() const noexcept;
	bool active() const noexcept;
	void run_steps(std::size_t steps);
	std::vector<std::complex<double>> reduced_density() const;
	void destroy() noexcept;

private:
	class Impl;
	std::unique_ptr<Impl> impl_;
};

class HEOMSolver {
public:
	HEOMSolver();
	explicit HEOMSolver(ContextOptions options);
	HEOMSolver(Context& context, System system, Bath bath, HierarchySpec hierarchy, SolverOptions options = {});

	Diagnostics validate_options() const;
	RunResult run_steps(std::size_t steps);
	RunResult run(const System& system, const HierarchySpec& hierarchy, const SolverOptions& options) const;

private:
	ContextOptions options_;
	Context* context_ = nullptr;
	System system_;
	Bath bath_;
	HierarchySpec hierarchy_;
	SolverOptions solverOptions_;
};

/*
 * HELIX public API contract (pre-1.0)
 *
 * ABI & SemVer policy:
 * 1. Pre-1.0 header API is shape-stable and additions-only. Header paths
 *    (helix/*.h) and the helix:: namespace are fixed.
 * 2. Binary ABI is NOT guaranteed across releases (pimpl-based evolution);
 *    Python wheels are rebuilt for every release.
 * 3. StatusCode enum values are append-only and stable: never removed or
 *    reused, never re-ordered or inserted mid-enum, and their semantics never
 *    changed.
 *    New validation failure modes map 1:1 to codes added with their validation
 *    paths, never pre-allocated. Diagnostic message text is NOT part of the
 *    stability contract.
 * 4. RunResult fields are append-only; new fields carry default values.
 *
 * Support matrix (per enum value: supported / validation-only / unsupported,
 * with target version where committed):
 * - SparseOperator/System::from_sparse is validation-only and backend-independent.
 * - SystemKind::LegacySpinGlass is supported through
 *   helix::examples::legacy_spin_glass_system(), a compatibility adapter for the
 *   current hard-coded model rather than a generic System schema.
 * - Bath::drude_lorentz_pade() and HierarchySpec::compiled_default() support the
 *   current compiled Drude-Lorentz/Pade and hierarchy defaults; non-default fields
 *   are unsupported.
 * - Bath::Kind::UserExponents is validation-only: invalid exponent structures
 *   report BathExponentsInvalid and valid structures report UnsupportedBath.
 *   The interface is frozen in v0.2-lite; execution targets Epic 32 / v0.3-lite.
 * - Precision::Single is supported. Precision::Double is unsupported
 *   (UnsupportedPrecision), target v0.3-lite.
 * - Backend::LegacyCudaSparse is supported. Backend::CudaSparse is unsupported
 *   (UnsupportedBackend), target v0.2-lite; Backend::CpuReference is unsupported
 *   and deferred/non-target until v1.x.
 * - SystemKind::Sparse construction is validation-only; execution is unsupported
 *   (UnsupportedExecution), target v1.0-minimal for the EmuPlat spin-boson/Drude
 *   scenario and v1.x for full support. SystemKind::Dense is validation-only and
 *   deferred to the non-default v1.x route. ResultMode::FinalState is supported
 *   on the legacy path; ObservableTrace and Trajectory are validation-only
 *   (UnsupportedExecution) and uncommitted.
 * - Concurrent contexts are unsupported (ConcurrentContextUnsupported) and
 *   deferred/unscheduled until v1.x.
 */

} // namespace helix
