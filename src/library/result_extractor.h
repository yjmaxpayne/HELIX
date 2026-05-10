#pragma once

#include <helix/types.h>

#include <complex>
#include <cstddef>
#include <vector>

namespace helix::library {

struct ReducedDensityExtraction
{
	std::vector<std::complex<double>> values;
	ReducedDensityShape shape;
};

class ResultExtractor {
public:
	static ReducedDensityExtraction final_reduced_density();
	static std::size_t hierarchy_size() noexcept;
};

} // namespace helix::library
