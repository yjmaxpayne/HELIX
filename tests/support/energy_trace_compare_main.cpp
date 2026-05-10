#include "energy_trace_comparator.h"

#include <cstdlib>
#include <iostream>

namespace {

bool parseDouble(const char* value, double& parsed)
{
	char* end = nullptr;
	parsed = std::strtod(value, &end);
	return end != value && *end == '\0';
}

bool parseRowCount(const char* value, std::size_t& parsed)
{
	char* end = nullptr;
	const unsigned long rows = std::strtoul(value, &end, 10);
	if(end == value || *end != '\0')
	{
		return false;
	}
	parsed = static_cast<std::size_t>(rows);
	return true;
}

} // namespace

int main(int argc, char** argv)
{
	if(argc != 4 && argc != 5)
	{
		std::cerr << "usage: energy_trace_compare <reference> <actual> <tolerance> [expected_rows]\n";
		return 2;
	}

	double tolerance = 0.0;
	if(!parseDouble(argv[3], tolerance) || tolerance < 0.0)
	{
		std::cerr << "invalid tolerance: " << argv[3] << "\n";
		return 2;
	}

	const auto result = helix::test::compareEnergyTracePrefix(argv[1], argv[2], tolerance);
	if(!result.ok)
	{
		std::cerr << result.failure_message << "\n";
		return 1;
	}

	if(argc == 5)
	{
		std::size_t expectedRows = 0;
		if(!parseRowCount(argv[4], expectedRows))
		{
			std::cerr << "invalid expected row count: " << argv[4] << "\n";
			return 2;
		}
		if(result.diff.compared_rows != expectedRows)
		{
			std::cerr << "expected " << expectedRows << " outputEnergy rows, got "
					<< result.diff.compared_rows << "\n";
			return 1;
		}
	}

	std::cout << "outputEnergy prefix matched: lines=" << result.diff.compared_rows
			  << " max_time_diff=" << result.diff.max_time_diff
			  << " max_energy_diff=" << result.diff.max_energy_diff << " tolerance=" << tolerance
			  << "\n";
	return 0;
}
