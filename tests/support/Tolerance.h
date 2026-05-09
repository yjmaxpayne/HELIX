#ifndef HELIX_TEST_SUPPORT_TOLERANCE_H
#define HELIX_TEST_SUPPORT_TOLERANCE_H

#include <algorithm>
#include <cmath>

namespace helix::test {

constexpr double kStrictTolerance = 1.0e-12;
constexpr double kDefaultTolerance = 1.0e-9;
constexpr double kNumericalTolerance = 1.0e-6;

inline bool near(double lhs, double rhs, double tolerance = kDefaultTolerance)
{
	return std::abs(lhs - rhs) <= tolerance;
}

inline bool nearRelative(
	double lhs,
	double rhs,
	double absoluteTolerance = kDefaultTolerance,
	double relativeTolerance = kNumericalTolerance)
{
	const double scale = std::max(std::abs(lhs), std::abs(rhs));
	return std::abs(lhs - rhs) <= absoluteTolerance + relativeTolerance * scale;
}

} // namespace helix::test

#endif // HELIX_TEST_SUPPORT_TOLERANCE_H
