#include "library/result_extractor.h"

#include "matrix_storage.h"
#include "parameters.h"

#include <stdexcept>
#include <thrust/copy.h>
#include <thrust/host_vector.h>

namespace helix::library {

ReducedDensityExtraction ResultExtractor::final_reduced_density()
{
	if(dRho.size() < static_cast<std::size_t>(Param::N2))
	{
		throw std::logic_error("ResultExtractor reduced density is not initialized");
	}

	thrust::host_vector<Complex> hostDensity(Param::N2);
	thrust::copy_n(dRho.begin(), Param::N2, hostDensity.begin());

	ReducedDensityExtraction extraction;
	extraction.shape.count = 1;
	extraction.shape.rows = static_cast<std::size_t>(Param::N);
	extraction.shape.cols = static_cast<std::size_t>(Param::N);
	extraction.shape.storageOrder = MatrixStorageOrder::RowMajor;
	extraction.values.reserve(hostDensity.size());
	for(const auto& value : hostDensity)
	{
		extraction.values.emplace_back(static_cast<double>(value.x), static_cast<double>(value.y));
	}

	return extraction;
}

std::size_t ResultExtractor::hierarchy_size() noexcept
{
	return hierarchySize < 0 ? 0 : static_cast<std::size_t>(hierarchySize);
}

} // namespace helix::library
