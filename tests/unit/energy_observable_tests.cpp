#include "library/energy_observable.h"
#include "support/assert.h"

#include <complex>
#include <stdexcept>
#include <vector>

namespace {

void testEnergyUsesHamiltonianAndDensityDiagonals(helix::test::Reporter& test)
{
	const std::vector<std::complex<double>> hamiltonian = {
		{2.0, 0.0}, {0.5, 0.0},
		{0.5, 0.0}, {4.0, 0.0},
	};
	const std::vector<std::complex<double>> densityDiagonal = {
		{0.25, 0.0},
		{0.75, 0.0},
	};

	const double energy = helix::library::energyFromDensityDiagonal(hamiltonian, densityDiagonal, 2);

	test.expectNear(energy, 3.5, 1.0e-12, "energy helper reuses row-major Hamiltonian diagonal semantics");
}

void testEnergyHelperKeepsLegacyRealPartSemantics(helix::test::Reporter& test)
{
	const std::vector<std::complex<double>> hamiltonian = {
		{2.0, 9.0}, {0.0, 0.0},
		{0.0, 0.0}, {4.0, 9.0},
	};
	const std::vector<std::complex<double>> densityDiagonal = {
		{0.25, 7.0},
		{0.75, 7.0},
	};

	const double energy = helix::library::energyFromDensityDiagonal(hamiltonian, densityDiagonal, 2);

	test.expectNear(energy, 3.5, 1.0e-12, "energy helper intentionally uses real diagonal parts");
}

void testEnergyHelperRejectsUndersizedInputs(helix::test::Reporter& test)
{
	bool caughtHamiltonian = false;
	try
	{
		(void)helix::library::energyFromDensityDiagonal({{1.0, 0.0}}, {{1.0, 0.0}}, 2);
	}
	catch(const std::invalid_argument&)
	{
		caughtHamiltonian = true;
	}

	bool caughtDensity = false;
	try
	{
		const std::vector<std::complex<double>> hamiltonian(4, {1.0, 0.0});
		(void)helix::library::energyFromDensityDiagonal(hamiltonian, {{1.0, 0.0}}, 2);
	}
	catch(const std::invalid_argument&)
	{
		caughtDensity = true;
	}

	test.expect(caughtHamiltonian, "energy helper rejects undersized Hamiltonian input");
	test.expect(caughtDensity, "energy helper rejects undersized density diagonal input");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testEnergyUsesHamiltonianAndDensityDiagonals(test);
	testEnergyHelperKeepsLegacyRealPartSemantics(test);
	testEnergyHelperRejectsUndersizedInputs(test);

	return test.finish("energy observable tests");
}
