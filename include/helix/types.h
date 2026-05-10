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
	ConcurrentContextUnsupported
};

struct Diagnostic {
	StatusCode code;
	std::string message;
};

class Diagnostics {
public:
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
	double inverseTemperature = 0.0;
	double damping = 0.0;
	double couplingStrength = 0.0;
	std::size_t padeTerms = 0;
	std::vector<std::complex<double>> residues;
	std::vector<double> frequencies;

	static Bath drude_lorentz_pade();
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

struct RunResult {
	std::vector<double> times;
	std::vector<std::complex<double>> reducedDensity;
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
 * HELIX v0.1 public API support matrix:
 *
 * - SparseOperator/System::from_sparse is validation-only and backend-independent.
 * - helix::examples::legacy_spin_glass_system() is a compatibility adapter for the current
 *   hard-coded legacy spin-glass model, not a generic System schema.
 * - Bath::drude_lorentz_pade() and HierarchySpec::compiled_default() map the current compiled
 *   Drude-Lorentz/Pade and hierarchy defaults; non-default fields report constrained/unsupported
 *   diagnostics in v0.1.
 * - Precision::Single is the only accepted v0.1 runtime precision; Precision::Double reports
 *   UnsupportedPrecision.
 * - Backend::LegacyCudaSparse is the only accepted v0.1 runtime backend option; CpuReference and
 *   CudaSparse report UnsupportedBackend until dedicated execution paths exist.
 * - Arbitrary sparse HEOM execution is not wired to the legacy runtime in v0.1. HEOMSolver reports
 *   UnsupportedExecution instead of silently running the hard-coded legacy adapter.
 * - Concurrent contexts are explicitly unsupported in v0.1 and report
 *   ConcurrentContextUnsupported.
 */

} // namespace helix
