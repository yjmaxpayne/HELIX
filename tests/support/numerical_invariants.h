#pragma once

#include "cuda_types.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <ostream>

namespace helix::test {

struct DiffStats {
	double maxAbs = 0.0;
	double maxRel = 0.0;
};

struct ComplexScalar {
	double real = 0.0;
	double imag = 0.0;
};

inline double realPart(const Complex& value)
{
	return static_cast<double>(value.x);
}

inline double imagPart(const Complex& value)
{
	return static_cast<double>(value.y);
}

inline bool isFinite(const Complex& value)
{
	return std::isfinite(realPart(value)) && std::isfinite(imagPart(value));
}

inline double magnitude(double real, double imag)
{
	return std::sqrt(real * real + imag * imag);
}

inline double magnitude(const Complex& value)
{
	return magnitude(realPart(value), imagPart(value));
}

inline void updateDiffStats(DiffStats& stats, double absDiff, double referenceScale)
{
	stats.maxAbs = std::max(stats.maxAbs, absDiff);
	if(referenceScale > 0.0)
	{
		stats.maxRel = std::max(stats.maxRel, absDiff / referenceScale);
	}
	else
	{
		stats.maxRel = std::max(stats.maxRel, absDiff);
	}
}

template<typename Vector>
bool allFinite(const Vector& values)
{
	for(size_t i = 0; i < values.size(); i++)
	{
		if(!isFinite(values[i]))
		{
			return false;
		}
	}
	return true;
}

template<typename Vector>
ComplexScalar traceBlock(const Vector& values, int matrixSize, int blockIndex)
{
	const size_t blockOffset = static_cast<size_t>(blockIndex) * matrixSize * matrixSize;
	ComplexScalar trace;
	for(int i = 0; i < matrixSize; i++)
	{
		const Complex& value = values[blockOffset + static_cast<size_t>(i) * matrixSize + i];
		trace.real += realPart(value);
		trace.imag += imagPart(value);
	}
	return trace;
}

inline DiffStats compareScalar(const ComplexScalar& actual, const ComplexScalar& expected)
{
	DiffStats stats;
	const double absDiff = magnitude(actual.real - expected.real, actual.imag - expected.imag);
	const double referenceScale = magnitude(expected.real, expected.imag);
	updateDiffStats(stats, absDiff, referenceScale);
	return stats;
}

template<typename Vector>
DiffStats hermiticityDiffBlock(const Vector& values, int matrixSize, int blockIndex)
{
	const size_t blockOffset = static_cast<size_t>(blockIndex) * matrixSize * matrixSize;
	DiffStats stats;
	for(int row = 0; row < matrixSize; row++)
	{
		for(int column = 0; column < matrixSize; column++)
		{
			const Complex& lhs = values[blockOffset + static_cast<size_t>(row) * matrixSize + column];
			const Complex& rhs = values[blockOffset + static_cast<size_t>(column) * matrixSize + row];
			const double absDiff = magnitude(
				realPart(lhs) - realPart(rhs),
				imagPart(lhs) + imagPart(rhs));
			const double referenceScale = std::max(magnitude(lhs), magnitude(rhs));
			updateDiffStats(stats, absDiff, referenceScale);
		}
	}
	return stats;
}

template<typename Vector>
DiffStats vectorDiff(const Vector& actual, const Vector& expected)
{
	DiffStats stats;
	const size_t count = std::min(actual.size(), expected.size());
	for(size_t i = 0; i < count; i++)
	{
		const double absDiff = magnitude(
			realPart(actual[i]) - realPart(expected[i]),
			imagPart(actual[i]) - imagPart(expected[i]));
		const double referenceScale = std::max(magnitude(actual[i]), magnitude(expected[i]));
		updateDiffStats(stats, absDiff, referenceScale);
	}
	if(actual.size() != expected.size())
	{
		updateDiffStats(stats, 1.0, 1.0);
	}
	return stats;
}

inline void printDiffStats(
	std::ostream& output,
	const char* name,
	const DiffStats& stats,
	double absoluteTolerance,
	double relativeTolerance,
	const char* reference)
{
	output << name << ": max_abs_diff=" << stats.maxAbs << " max_rel_diff=" << stats.maxRel
		   << " abs_tolerance=" << absoluteTolerance << " rel_tolerance=" << relativeTolerance
		   << " reference=" << reference << '\n';
}

} // namespace helix::test
