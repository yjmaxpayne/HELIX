#ifndef HELIX_TEST_SUPPORT_ENERGY_TRACE_COMPARATOR_H
#define HELIX_TEST_SUPPORT_ENERGY_TRACE_COMPARATOR_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace helix::test {

struct EnergyDiff {
	std::size_t compared_rows = 0;
	double max_time_diff = 0.0;
	double max_energy_diff = 0.0;
};

struct EnergyTraceComparison {
	bool ok = false;
	EnergyDiff diff;
	std::string failure_message;
};

namespace energy_trace_detail {

struct EnergyRow {
	double time = 0.0;
	double energy = 0.0;
};

inline std::string rowString(const EnergyRow& row)
{
	std::ostringstream out;
	out << "(" << row.time << "," << row.energy << ")";
	return out.str();
}

inline bool readEnergyRows(
	const std::filesystem::path& path,
	std::vector<EnergyRow>& rows,
	std::string& failureMessage)
{
	std::ifstream input(path);
	if(!input)
	{
		failureMessage = "failed to open outputEnergy file: " + path.string();
		return false;
	}

	std::string line;
	std::size_t lineNumber = 0;
	while(std::getline(input, line))
	{
		lineNumber++;
		if(line.find_first_not_of(" \t\r\n") == std::string::npos)
		{
			continue;
		}

		std::istringstream parsed(line);
		EnergyRow row;
		if(!(parsed >> row.time >> row.energy))
		{
			std::ostringstream message;
			message << "failed to parse outputEnergy line " << lineNumber << " in " << path.string();
			failureMessage = message.str();
			return false;
		}
		rows.push_back(row);
	}

	return true;
}

} // namespace energy_trace_detail

inline EnergyTraceComparison compareEnergyTracePrefix(
	const std::filesystem::path& referencePath,
	const std::filesystem::path& actualPath,
	double tolerance)
{
	using energy_trace_detail::EnergyRow;

	EnergyTraceComparison result;
	std::vector<EnergyRow> reference;
	std::vector<EnergyRow> actual;

	if(!energy_trace_detail::readEnergyRows(referencePath, reference, result.failure_message))
	{
		return result;
	}
	if(!energy_trace_detail::readEnergyRows(actualPath, actual, result.failure_message))
	{
		return result;
	}

	if(reference.empty())
	{
		result.failure_message = "reference outputEnergy has no rows";
		return result;
	}
	if(actual.empty())
	{
		result.failure_message = "run produced no outputEnergy rows";
		return result;
	}

	for(std::size_t i = 0; i < actual.size(); i++)
	{
		const std::size_t lineNumber = i + 1;
		if(i >= reference.size())
		{
			std::ostringstream message;
			message << "run has more rows than reference at line " << lineNumber;
			result.failure_message = message.str();
			return result;
		}

		const EnergyRow& referenceRow = reference[i];
		const EnergyRow& actualRow = actual[i];
		const double timeDiff = std::abs(actualRow.time - referenceRow.time);
		const double energyDiff = std::abs(actualRow.energy - referenceRow.energy);

		result.diff.compared_rows = lineNumber;
		result.diff.max_time_diff = std::max(result.diff.max_time_diff, timeDiff);
		result.diff.max_energy_diff = std::max(result.diff.max_energy_diff, energyDiff);

		if(timeDiff > tolerance || energyDiff > tolerance)
		{
			std::ostringstream message;
			message << "mismatch line " << lineNumber << ": reference="
					<< energy_trace_detail::rowString(referenceRow) << " actual="
					<< energy_trace_detail::rowString(actualRow) << " max_time_diff=" << timeDiff
					<< " max_energy_diff=" << energyDiff << " tolerance=" << tolerance;
			result.failure_message = message.str();
			return result;
		}
	}

	result.ok = true;
	return result;
}

} // namespace helix::test

#endif // HELIX_TEST_SUPPORT_ENERGY_TRACE_COMPARATOR_H
