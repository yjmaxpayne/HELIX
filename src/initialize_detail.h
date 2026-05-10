#pragma once

#include "matrix_storage.h"
#include <array>
#include <cmath>
#include <thrust/equal.h>
#include <thrust/functional.h>
#include <thrust/reduce.h>

namespace initialize_detail {

inline int spinCountFromHilbertSize(int hilbertSize)
{
	return static_cast<int>((std::log(static_cast<double>(hilbertSize)) / std::log(2.0)) + 0.5);
}

template <size_t N>
inline bool containsMask(const std::array<int, N>& masks, int mask)
{
	for(size_t i = 0; i < N; i++)
	{
		if(masks[i] == mask)
		{
			return true;
		}
	}
	return false;
}

inline bool isDenseFlipMask(int mask)
{
	static const std::array<int, 13> masks = {
		1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
	};
	return containsMask(masks, mask);
}

inline bool isSparseFlipMask(int mask)
{
	static const std::array<int, 9> masks = {
		1, 2, 4, 8, 16, 32, 64, 128, 256
	};
	return containsMask(masks, mask);
}

inline void setCoupling(host_vector<double>& couplings, int spinCount, int row, int column, double value)
{
	couplings[row * spinCount + column] = value;
}

inline void addLinearCouplings(host_vector<double>& couplings, int spinCount, double value)
{
	for(int i = 0; i < spinCount; i++)
	{
		for(int j = 0; j < spinCount; j++)
		{
			setCoupling(couplings, spinCount, i, j, (i - j == -1 || i - j == 1) ? value : 0.0);
		}
	}
}

inline void addTriangularNineSpinCouplings(host_vector<double>& couplings, double value)
{
	static const std::array<std::array<int, 2>, 32> edges = {{
		{{0, 1}}, {{0, 7}},
		{{1, 0}}, {{1, 7}}, {{1, 2}}, {{1, 8}},
		{{2, 1}}, {{2, 3}}, {{2, 8}},
		{{3, 2}}, {{3, 4}}, {{3, 5}}, {{3, 8}},
		{{4, 3}}, {{4, 5}},
		{{5, 4}}, {{5, 6}}, {{5, 3}}, {{5, 8}},
		{{6, 5}}, {{6, 7}}, {{6, 8}},
		{{7, 6}}, {{7, 0}}, {{7, 1}}, {{7, 8}},
		{{8, 1}}, {{8, 2}}, {{8, 3}}, {{8, 5}}, {{8, 6}}, {{8, 7}}
	}};
	for(size_t i = 0; i < edges.size(); i++)
	{
		setCoupling(couplings, 9, edges[i][0], edges[i][1], value);
	}
}

inline void addSquareNineSpinCouplings(host_vector<double>& couplings, double value)
{
	static const std::array<std::array<int, 2>, 24> edges = {{
		{{0, 1}}, {{0, 7}},
		{{1, 0}}, {{1, 2}}, {{1, 8}},
		{{2, 1}}, {{2, 3}},
		{{3, 2}}, {{3, 4}}, {{3, 8}},
		{{4, 3}}, {{4, 5}},
		{{5, 4}}, {{5, 6}}, {{5, 8}},
		{{6, 5}}, {{6, 7}},
		{{7, 6}}, {{7, 0}}, {{7, 8}},
		{{8, 1}}, {{8, 3}}, {{8, 5}}, {{8, 7}}
	}};
	for(size_t i = 0; i < edges.size(); i++)
	{
		setCoupling(couplings, 9, edges[i][0], edges[i][1], value);
	}
}

inline host_vector<double> buildCouplingMatrix(int spinCount, double value, bool isSquare)
{
	host_vector<double> couplings(spinCount * spinCount, 0.0);
	if(spinCount != 9)
	{
		addLinearCouplings(couplings, spinCount, value);
	}
	else if(isSquare)
	{
		addSquareNineSpinCouplings(couplings, value);
	}
	else
	{
		addTriangularNineSpinCouplings(couplings, value);
	}
	return couplings;
}

inline double spinProjection(int state, int spin, double omega0)
{
	return (((state >> spin) & 1) == 1) ? 0.5 * omega0 : -0.5 * omega0;
}

inline host_vector<double> spinProjections(int state, int spinCount, double omega0)
{
	host_vector<double> projections(spinCount);
	for(int spin = 0; spin < spinCount; spin++)
	{
		projections[spin] = spinProjection(state, spin, omega0);
	}
	return projections;
}

inline double sumProjections(const host_vector<double>& projections)
{
	double sum = 0.0;
	for(size_t i = 0; i < projections.size(); i++)
	{
		sum += projections[i];
	}
	return sum;
}

inline double hamiltonianDiagonal(
	const host_vector<double>& couplings,
	const host_vector<double>& projections,
	int spinCount)
{
	double total = sumProjections(projections);
	for(int j = 0; j < spinCount; j++)
	{
		for(int k = 0; k < j; k++)
		{
			total += couplings[j * spinCount + k] * projections[j] * projections[k];
		}
	}
	return total;
}

inline int hierarchySizeFor(int modeCount, int maxLevel)
{
	if(modeCount == 1)
	{
		return maxLevel;
	}

	host_vector<int> numbers(maxLevel);
	for(int i = 0; i < maxLevel; i++)
	{
		numbers[i] = hierarchySizeFor(modeCount - 1, maxLevel - i);
	}
	return thrust::reduce(numbers.begin(), numbers.end(), 0, thrust::plus<int>());
}

inline void appendHierarchyRows(
	int depth,
	int modeCount,
	int& rowCount,
	const host_vector<int>& prefix,
	host_vector< host_vector<int> >& rows,
	int maxLevel)
{
	if(depth == modeCount)
	{
		rows[rowCount] = prefix;
		rowCount++;
	}
	else if(depth == 0)
	{
		for(int i = 0; i < maxLevel; i++)
		{
			host_vector<int> next(1);
			next[0] = i;
			appendHierarchyRows(depth + 1, modeCount, rowCount, next, rows, maxLevel);
		}
	}
	else
	{
		for(int i = 0; i < maxLevel; i++)
		{
			int sum = (prefix.size() > 1) ? thrust::reduce(prefix.begin() + 1, prefix.end(), i) : 0;
			sum += prefix[0];
			if(sum < maxLevel)
			{
				host_vector<int> next(prefix.size());
				for(size_t k = 0; k < prefix.size(); k++)
				{
					next[k] = prefix[k];
				}
				next.push_back(i);
				appendHierarchyRows(depth + 1, modeCount, rowCount, next, rows, maxLevel);
			}
		}
	}
}

inline host_vector< host_vector<int> > buildHierarchyRows(int modeCount, int maxLevel)
{
	host_vector< host_vector<int> > rows(hierarchySizeFor(modeCount, maxLevel), host_vector<int>(modeCount));
	int rowCount = 0;
	appendHierarchyRows(0, modeCount, rowCount, host_vector<int>(0), rows, maxLevel);
	return rows;
}

inline host_vector<int> flattenRows(const host_vector< host_vector<int> >& rows, int columnCount)
{
	host_vector<int> flattened(rows.size() * columnCount);
	for(size_t i = 0; i < flattened.size(); i++)
	{
		flattened[i] = rows[i / columnCount][i % columnCount];
	}
	return flattened;
}

inline void buildHierarchyEdges(
	const host_vector< host_vector<int> >& hierarchy,
	host_vector< host_vector<int> >& result,
	int hierarchyCount,
	int modeCount)
{
	for(int i = 0; i < hierarchyCount; i++)
	{
		for(int j = 0; j < modeCount * 2; j++)
		{
			result[i][j] = hierarchyCount;
		}
	}

	host_vector<int> numOffset(modeCount);
	for(int i = 0; i < hierarchyCount; i++)
	{
		for(int j = 0; j < modeCount; j++)
		{
			for(int k = 0; k < modeCount; k++)
			{
				numOffset[k] = hierarchy[i][k] + ((j == k) ? 1 : 0);
			}

			for(int k = 0; k < hierarchyCount; k++)
			{
				if(thrust::equal(numOffset.begin(), numOffset.end(), hierarchy[k].begin()))
				{
					result[i][j] = k;
					result[k][j + modeCount] = i;
					break;
				}
			}
		}
	}
}

} // namespace initialize_detail
