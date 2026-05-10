#pragma once

#include <complex>
#include <cstddef>
#include <vector>

namespace helix::library {

struct LegacyRuntimeSessionConfig
{
	int integrationOrder = 4;
	double step = 0.1;
};

class LegacyRuntimeSession
{
public:
	explicit LegacyRuntimeSession(LegacyRuntimeSessionConfig config);
	~LegacyRuntimeSession() noexcept;

	LegacyRuntimeSession(const LegacyRuntimeSession&) = delete;
	LegacyRuntimeSession& operator=(const LegacyRuntimeSession&) = delete;
	LegacyRuntimeSession(LegacyRuntimeSession&&) = delete;
	LegacyRuntimeSession& operator=(LegacyRuntimeSession&&) = delete;

	void create();
	void run_steps(std::size_t steps);
	std::vector<std::complex<double>> reduced_density() const;
	void destroy() noexcept;
	bool active() const noexcept;

private:
	void requireActive() const;
	void restoreParameters() noexcept;

	LegacyRuntimeSessionConfig config_;
	bool active_ = false;
	int previousIntegrationOrder_ = 4;
	double previousStep_ = 0.1;
};

bool legacyRuntimeStorageReleased();

} // namespace helix::library
