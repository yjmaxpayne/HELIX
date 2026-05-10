#pragma once

#include <complex>
#include <cstddef>
#include <vector>

namespace helix::library {

double energyFromDensityDiagonal(
	const std::vector<std::complex<double>>& hamiltonianRowMajor,
	const std::vector<std::complex<double>>& densityDiagonal,
	std::size_t dimension);

} // namespace helix::library
