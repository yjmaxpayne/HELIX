#include "library/result_extractor.h"

#include "library/backend_profiling.h"
#include "matrix_storage.h"
#include "parameters.h"

#include <chrono>
#include <cuda_runtime.h>
#include <stdexcept>
#include <string>
#include <thrust/copy.h>
#include <thrust/host_vector.h>

namespace helix::library {

namespace {

using Clock = std::chrono::steady_clock;

double elapsedMilliseconds(Clock::time_point start, Clock::time_point stop)
{
	return std::chrono::duration<double, std::milli>(stop - start).count();
}

void requireCuda(cudaError_t status, const char* action)
{
	if(status != cudaSuccess)
	{
		throw std::runtime_error(std::string("Failed to ") + action + ": " + cudaGetErrorString(status));
	}
}

} // namespace

ReducedDensityExtraction ResultExtractor::final_reduced_density()
{
	if(dRho.size() < static_cast<std::size_t>(Param::N2))
	{
		throw std::logic_error("ResultExtractor reduced density is not initialized");
	}

	const bool collectProfiling = backendProfilingEnabled();
	BackendResultExtractionProfilingCounters profiling;
	if(collectProfiling)
	{
		const auto syncStart = Clock::now();
		requireCuda(cudaDeviceSynchronize(), "synchronize before reduced-density extraction");
		const auto syncStop = Clock::now();
		profiling.syncWaitMs = elapsedMilliseconds(syncStart, syncStop);
		profiling.d2hBytes = static_cast<std::size_t>(Param::N2) * sizeof(Complex);
		profiling.elementCount = static_cast<std::size_t>(Param::N2);
	}

	const auto allocationStart = Clock::now();
	thrust::host_vector<Complex> hostDensity(Param::N2);
	const auto allocationStop = Clock::now();
	if(collectProfiling)
	{
		profiling.hostAllocationMs = elapsedMilliseconds(allocationStart, allocationStop);
	}

	const auto copyStart = Clock::now();
	thrust::copy_n(dRho.begin(), Param::N2, hostDensity.begin());
	const auto copyStop = Clock::now();
	if(collectProfiling)
	{
		profiling.d2hCopyMs = elapsedMilliseconds(copyStart, copyStop);
	}

	const auto conversionStart = Clock::now();
	ReducedDensityExtraction extraction;
	extraction.shape.count = 1;
	extraction.shape.rows = static_cast<std::size_t>(Param::N);
	extraction.shape.cols = static_cast<std::size_t>(Param::N);
	// Public RunResult values stay row-major even if a future backend uses a private layout.
	extraction.shape.storageOrder = MatrixStorageOrder::RowMajor;
	extraction.values.reserve(hostDensity.size());
	for(const auto& value : hostDensity)
	{
		extraction.values.emplace_back(static_cast<double>(value.x), static_cast<double>(value.y));
	}
	const auto conversionStop = Clock::now();
	if(collectProfiling)
	{
		profiling.conversionMs = elapsedMilliseconds(conversionStart, conversionStop);
		recordResultExtractionProfiling(profiling);
	}

	return extraction;
}

std::size_t ResultExtractor::hierarchy_size() noexcept
{
	return hierarchySize < 0 ? 0 : static_cast<std::size_t>(hierarchySize);
}

} // namespace helix::library
