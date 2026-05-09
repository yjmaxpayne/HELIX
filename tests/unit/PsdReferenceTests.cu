#include "Parameters.h"
#include "Psd/Psd.h"
#include "support/Assert.h"

namespace {

constexpr double kPsdReferenceTolerance = 1.0e-12;

void testDefaultBosonicPsdReference(helix::test::Reporter& test)
{
	thrust::host_vector<double> poles;
	thrust::host_vector<double> residues;
	double remainder = -1.0;
	double truncation = -1.0;

	const bool ok = getPsdPoleResidue(Param::KMax, false, NMinus1_N, poles, residues, remainder, truncation);

	test.expect(ok, "PSD reference computation succeeds for default KMax");
	test.expect(poles.size() == static_cast<size_t>(Param::KMax + 1), "PSD poles vector keeps legacy KMax+1 size");
	test.expect(residues.size() == static_cast<size_t>(Param::KMax + 1), "PSD residues vector keeps legacy KMax+1 size");

	// Reference: high-precision eigensystem of the NMinus1_N Pade matrices for KMax=2, bosonic case.
	test.expectNear(poles[0], 6.3059391442248085, kPsdReferenceTolerance, "PSD pole[0] matches KMax=2 reference");
	test.expectNear(poles[1], 19.499618752922666, kPsdReferenceTolerance, "PSD pole[1] matches KMax=2 reference");
	test.expectNear(residues[0], 1.0328241810241552, kPsdReferenceTolerance, "PSD residue[0] matches KMax=2 reference");
	test.expectNear(residues[1], 5.9671758189758448, kPsdReferenceTolerance, "PSD residue[1] matches KMax=2 reference");
	test.expectNear(remainder, 0.0, kPsdReferenceTolerance, "NMinus1_N PSD remainder remains zero");
	test.expectNear(truncation, 0.0, kPsdReferenceTolerance, "NMinus1_N PSD truncation remains zero");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testDefaultBosonicPsdReference(test);

	return test.finish("PSD reference tests");
}
