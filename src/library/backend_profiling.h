#pragma once

#include <cstddef>
#include <optional>

namespace helix::library {

struct BackendSpmmProfilingCounters
{
	std::optional<std::size_t> callCount;
	std::optional<double> timeMs;
	std::optional<std::size_t> descriptorCreateCount;
	std::optional<std::size_t> workspaceAllocCount;
	std::optional<std::size_t> workspaceBytes;
	std::optional<std::size_t> bufferSizeQueryCount;
};

struct BackendTransposeProfilingCounters
{
	std::optional<std::size_t> callCount;
	std::optional<double> timeMs;
	std::optional<std::size_t> bytes;
};

struct BackendD2DCopyProfilingCounters
{
	std::optional<std::size_t> copyCount;
	std::optional<double> timeMs;
	std::optional<std::size_t> bytes;
};

struct BackendSyncProfilingCounters
{
	std::optional<std::size_t> deviceSynchronizeCount;
	std::optional<double> syncWaitMs;
};

struct BackendResultExtractionProfilingCounters
{
	std::optional<double> syncWaitMs;
	std::optional<double> hostAllocationMs;
	std::optional<double> d2hCopyMs;
	std::optional<double> conversionMs;
	std::optional<std::size_t> d2hBytes;
	std::optional<std::size_t> elementCount;
};

struct BackendProfilingCounters
{
	BackendSpmmProfilingCounters spmm;
	BackendTransposeProfilingCounters transpose;
	BackendD2DCopyProfilingCounters d2dCopy;
	BackendSyncProfilingCounters sync;
	BackendResultExtractionProfilingCounters resultExtraction;
};

class ScopedBackendProfiling {
public:
	explicit ScopedBackendProfiling(bool enabled = true) noexcept;
	~ScopedBackendProfiling() noexcept;

	ScopedBackendProfiling(const ScopedBackendProfiling&) = delete;
	ScopedBackendProfiling& operator=(const ScopedBackendProfiling&) = delete;

	BackendProfilingCounters snapshot() const;

private:
	bool previousEnabled_ = false;
};

bool backendProfilingEnabled() noexcept;
void setBackendProfilingEnabled(bool enabled) noexcept;
void resetBackendProfilingCounters() noexcept;
BackendProfilingCounters snapshotBackendProfilingCounters();
void recordSpmmProfiling(const BackendSpmmProfilingCounters& counters) noexcept;
void recordTransposeProfiling(const BackendTransposeProfilingCounters& counters) noexcept;
void recordD2DCopyProfiling(const BackendD2DCopyProfilingCounters& counters) noexcept;
void recordResultExtractionProfiling(const BackendResultExtractionProfilingCounters& counters) noexcept;

} // namespace helix::library
