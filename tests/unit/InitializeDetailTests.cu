#include "InitializeDetail.h"
#include "support/Assert.h"
#include "support/Tolerance.h"

namespace {

using helix::test::Reporter;

bool near(double lhs, double rhs)
{
	return helix::test::near(lhs, rhs, helix::test::kStrictTolerance);
}

int countNonZero(const host_vector<double>& values)
{
	int count = 0;
	for(size_t i = 0; i < values.size(); i++)
	{
		if(!near(values[i], 0.0))
		{
			count++;
		}
	}
	return count;
}

void testSpinFlipMasks(Reporter& test)
{
	using namespace initialize_detail;

	test.expect(spinCountFromHilbertSize(1024) == 10, "1024-dimensional Hilbert space has 10 spins");
	test.expect(isDenseFlipMask(512), "dense path keeps the legacy 512 flip mask");
	test.expect(isDenseFlipMask(4096), "dense path keeps the legacy 4096 flip mask");
	test.expect(!isDenseFlipMask(3), "dense path rejects non-power-of-two masks");
	test.expect(isSparseFlipMask(256), "sparse path keeps the legacy 256 flip mask");
	test.expect(!isSparseFlipMask(512), "sparse path preserves the legacy 512-mask omission");
}

void testCouplingMatrices(Reporter& test)
{
	using namespace initialize_detail;

	const double coupling = 0.6;
	host_vector<double> linear = buildCouplingMatrix(4, coupling, false);
	test.expect(countNonZero(linear) == 6, "4-spin linear chain has 6 directed nearest-neighbor couplings");
	test.expect(near(linear[0 * 4 + 1], coupling), "linear chain connects 0 -> 1");
	test.expect(near(linear[1 * 4 + 0], coupling), "linear chain connects 1 -> 0");
	test.expect(near(linear[0 * 4 + 2], 0.0), "linear chain does not connect 0 -> 2");

	host_vector<double> triangular = buildCouplingMatrix(9, coupling, false);
	test.expect(countNonZero(triangular) == 32, "9-spin triangular lattice has 32 directed couplings");
	test.expect(near(triangular[1 * 9 + 7], coupling), "triangular lattice includes 1 -> 7");
	test.expect(near(triangular[7 * 9 + 1], coupling), "triangular lattice includes 7 -> 1");

	host_vector<double> square = buildCouplingMatrix(9, coupling, true);
	test.expect(countNonZero(square) == 24, "9-spin square lattice has 24 directed couplings");
	test.expect(near(square[1 * 9 + 7], 0.0), "square lattice excludes triangular edge 1 -> 7");
	test.expect(near(square[1 * 9 + 8], coupling), "square lattice keeps 1 -> 8");
}

void testProjectionAndDiagonalEnergy(Reporter& test)
{
	using namespace initialize_detail;

	host_vector<double> couplings = buildCouplingMatrix(3, 0.6, false);
	host_vector<double> projections = spinProjections(0, 3, 1.0);

	test.expect(near(projections[0], -0.5), "spin 0 projection for state 0");
	test.expect(near(projections[1], -0.5), "spin 1 projection for state 0");
	test.expect(near(sumProjections(projections), -1.5), "projection sum for state 0");
	test.expect(near(hamiltonianDiagonal(couplings, projections, 3), -1.2), "diagonal energy preserves legacy accumulation");
}

void testHierarchyRowsAndEdges(Reporter& test)
{
	using namespace initialize_detail;

	const int modeCount = 3;
	const int maxLevel = 3;
	host_vector< host_vector<int> > rows = buildHierarchyRows(modeCount, maxLevel);

	test.expect(hierarchySizeFor(modeCount, maxLevel) == 10, "3 modes with max level 3 has 10 hierarchy rows");
	test.expect(rows.size() == 10, "buildHierarchyRows returns the expected row count");

	for(size_t i = 0; i < rows.size(); i++)
	{
		int sum = 0;
		test.expect(rows[i].size() == modeCount, "hierarchy row has the expected mode count");
		for(int j = 0; j < modeCount; j++)
		{
			sum += rows[i][j];
		}
		test.expect(sum < maxLevel, "hierarchy row sum stays below max level");
	}

	host_vector<int> flattened = flattenRows(rows, modeCount);
	test.expect(flattened.size() == rows.size() * modeCount, "flattenRows keeps all hierarchy entries");
	test.expect(flattened[0] == rows[0][0], "flattenRows preserves row-major order");

	const int hierarchyCount = static_cast<int>(rows.size());
	host_vector< host_vector<int> > edges(hierarchyCount, host_vector<int>(modeCount * 2));
	buildHierarchyEdges(rows, edges, hierarchyCount, modeCount);

	for(int i = 0; i < hierarchyCount; i++)
	{
		for(int j = 0; j < modeCount; j++)
		{
			int up = edges[i][j];
			if(up == hierarchyCount)
			{
				continue;
			}

			test.expect(up >= 0 && up < hierarchyCount, "up edge points to a valid hierarchy row");
			test.expect(edges[up][j + modeCount] == i, "down edge is reciprocal to up edge");
			for(int k = 0; k < modeCount; k++)
			{
				int expected = rows[i][k] + ((j == k) ? 1 : 0);
				test.expect(rows[up][k] == expected, "up edge increments only the selected mode");
			}
		}
	}
}

} // namespace

int main()
{
	Reporter test;

	testSpinFlipMasks(test);
	testCouplingMatrices(test);
	testProjectionAndDiagonalEnergy(test);
	testHierarchyRowsAndEdges(test);

	return test.finish("initialize detail tests");
}
