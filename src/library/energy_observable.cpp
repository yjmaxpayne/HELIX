#include "library/energy_observable.h"

#include <limits>
#include <stdexcept>

namespace helix::library {

double energyFromDensityDiagonal(
	const std::vector<std::complex<double>>& hamiltonianRowMajor,
	const std::vector<std::complex<double>>& densityDiagonal,
	std::size_t dimension)
{
	if(dimension == 0)
	{
		return 0.0;
	}
	if(dimension > std::numeric_limits<std::size_t>::max() / dimension)
	{
		throw std::invalid_argument("energy helper dimension is too large");
	}

	const std::size_t matrixSize = dimension * dimension;
	if(hamiltonianRowMajor.size() < matrixSize)
	{
		throw std::invalid_argument("energy helper Hamiltonian input is smaller than dimension squared");
	}
	if(densityDiagonal.size() < dimension)
	{
		throw std::invalid_argument("energy helper density diagonal input is smaller than dimension");
	}

	double energy = 0.0;
	for(std::size_t row = 0; row < dimension; ++row)
	{
		const std::size_t diagonalIndex = row * dimension + row;
		energy += hamiltonianRowMajor[diagonalIndex].real() * densityDiagonal[row].real();
	}
	return energy;
}

} // namespace helix::library
