#include "library/backend_profiling.h"

#include <algorithm>

namespace helix::library {

namespace {

struct BackendProfilingState
{
	bool enabled = false;
	BackendProfilingCounters counters;
};

BackendProfilingState& profilingState() noexcept
{
	thread_local BackendProfilingState state;
	return state;
}

template<typename T>
void addOptional(std::optional<T>& target, const std::optional<T>& value) noexcept
{
	if(!value.has_value())
	{
		return;
	}
	target = target.value_or(T{}) + *value;
}

void maxOptional(std::optional<std::size_t>& target, const std::optional<std::size_t>& value) noexcept
{
	if(!value.has_value())
	{
		return;
	}
	target = std::max(target.value_or(std::size_t{}), *value);
}

} // namespace

ScopedBackendProfiling::ScopedBackendProfiling(bool enabled) noexcept
	: previousEnabled_(backendProfilingEnabled())
{
	resetBackendProfilingCounters();
	setBackendProfilingEnabled(enabled);
}

ScopedBackendProfiling::~ScopedBackendProfiling() noexcept
{
	setBackendProfilingEnabled(previousEnabled_);
}

BackendProfilingCounters ScopedBackendProfiling::snapshot() const
{
	return snapshotBackendProfilingCounters();
}

bool backendProfilingEnabled() noexcept
{
	return profilingState().enabled;
}

void setBackendProfilingEnabled(bool enabled) noexcept
{
	profilingState().enabled = enabled;
}

void resetBackendProfilingCounters() noexcept
{
	profilingState().counters = BackendProfilingCounters{};
}

BackendProfilingCounters snapshotBackendProfilingCounters()
{
	return profilingState().counters;
}

void recordSpmmProfiling(const BackendSpmmProfilingCounters& counters) noexcept
{
	if(!backendProfilingEnabled())
	{
		return;
	}

	BackendSpmmProfilingCounters& snapshot = profilingState().counters.spmm;
	addOptional(snapshot.callCount, counters.callCount);
	addOptional(snapshot.timeMs, counters.timeMs);
	addOptional(snapshot.descriptorCreateCount, counters.descriptorCreateCount);
	addOptional(snapshot.workspaceAllocCount, counters.workspaceAllocCount);
	maxOptional(snapshot.workspaceBytes, counters.workspaceBytes);
	addOptional(snapshot.bufferSizeQueryCount, counters.bufferSizeQueryCount);
}

void recordTransposeProfiling(const BackendTransposeProfilingCounters& counters) noexcept
{
	if(!backendProfilingEnabled())
	{
		return;
	}

	BackendTransposeProfilingCounters& snapshot = profilingState().counters.transpose;
	addOptional(snapshot.callCount, counters.callCount);
	addOptional(snapshot.timeMs, counters.timeMs);
	addOptional(snapshot.bytes, counters.bytes);
}

void recordD2DCopyProfiling(const BackendD2DCopyProfilingCounters& counters) noexcept
{
	if(!backendProfilingEnabled())
	{
		return;
	}

	BackendD2DCopyProfilingCounters& snapshot = profilingState().counters.d2dCopy;
	addOptional(snapshot.copyCount, counters.copyCount);
	addOptional(snapshot.timeMs, counters.timeMs);
	addOptional(snapshot.bytes, counters.bytes);
}

void recordResultExtractionProfiling(const BackendResultExtractionProfilingCounters& counters) noexcept
{
	if(!backendProfilingEnabled())
	{
		return;
	}

	BackendProfilingCounters& snapshot = profilingState().counters;
	snapshot.resultExtraction = counters;
	if(counters.syncWaitMs.has_value())
	{
		const std::size_t previousCount = snapshot.sync.deviceSynchronizeCount.value_or(0);
		const double previousWait = snapshot.sync.syncWaitMs.value_or(0.0);
		snapshot.sync.deviceSynchronizeCount = previousCount + 1;
		snapshot.sync.syncWaitMs = previousWait + *counters.syncWaitMs;
	}
}

} // namespace helix::library
