#include "support/assert.h"
#include "support/energy_trace_comparator.h"
#include "support/temp_dir.h"

#include <filesystem>
#include <fstream>
#include <string>

namespace {

using helix::test::compareEnergyTracePrefix;
using helix::test::Reporter;
using helix::test::TempDir;

void writeText(const std::filesystem::path& path, const std::string& text)
{
	std::ofstream out(path);
	out << text;
}

void testMatchingSyntheticPrefix(Reporter& test)
{
	TempDir temp("helix-energy-match-");
	const auto reference = temp.path() / "reference.txt";
	const auto actual = temp.path() / "actual.txt";

	writeText(reference, "0 1.0\n0.1 0.9\n0.2 0.8\n");
	writeText(actual, "0 1.0\n0.1 0.9000001\n");

	const auto result = compareEnergyTracePrefix(reference, actual, 1.0e-5);

	test.expect(result.ok, "matching prefix succeeds");
	test.expect(result.diff.compared_rows == 2, "matching prefix reports compared row count");
	test.expectNear(result.diff.max_time_diff, 0.0, 1.0e-12, "matching prefix has zero max time diff");
	test.expectNear(result.diff.max_energy_diff, 1.0e-7, 1.0e-12, "matching prefix reports max energy diff");
}

void testEnergyToleranceFailureMessage(Reporter& test)
{
	TempDir temp("helix-energy-fail-");
	const auto reference = temp.path() / "reference.txt";
	const auto actual = temp.path() / "actual.txt";

	writeText(reference, "0 1.0\n0.1 0.9\n");
	writeText(actual, "0 1.0\n0.1 0.95\n");

	const auto result = compareEnergyTracePrefix(reference, actual, 1.0e-5);

	test.expect(!result.ok, "energy mismatch fails");
	test.expect(result.failure_message.find("line 2") != std::string::npos, "failure mentions line number");
	test.expect(result.failure_message.find("reference=(0.1,0.9)") != std::string::npos, "failure mentions reference row");
	test.expect(result.failure_message.find("actual=(0.1,0.95)") != std::string::npos, "failure mentions actual row");
	test.expect(result.failure_message.find("tolerance=1e-05") != std::string::npos, "failure mentions tolerance");
}

void testTimeToleranceFailure(Reporter& test)
{
	TempDir temp("helix-time-fail-");
	const auto reference = temp.path() / "reference.txt";
	const auto actual = temp.path() / "actual.txt";

	writeText(reference, "0 1.0\n0.1 0.9\n");
	writeText(actual, "0 1.0\n0.1001 0.9\n");

	const auto result = compareEnergyTracePrefix(reference, actual, 1.0e-5);

	test.expect(!result.ok, "time mismatch fails");
	test.expect(result.failure_message.find("max_time_diff") != std::string::npos, "time failure reports time diff");
}

void testEmptyActualFails(Reporter& test)
{
	TempDir temp("helix-empty-fail-");
	const auto reference = temp.path() / "reference.txt";
	const auto actual = temp.path() / "actual.txt";

	writeText(reference, "0 1.0\n");
	writeText(actual, "");

	const auto result = compareEnergyTracePrefix(reference, actual, 1.0e-5);

	test.expect(!result.ok, "empty actual output fails");
	test.expect(result.failure_message.find("no outputEnergy rows") != std::string::npos, "empty failure is specific");
}

void testActualLongerThanReferenceFails(Reporter& test)
{
	TempDir temp("helix-long-fail-");
	const auto reference = temp.path() / "reference.txt";
	const auto actual = temp.path() / "actual.txt";

	writeText(reference, "0 1.0\n");
	writeText(actual, "0 1.0\n0.1 0.9\n");

	const auto result = compareEnergyTracePrefix(reference, actual, 1.0e-5);

	test.expect(!result.ok, "actual longer than reference fails");
	test.expect(result.failure_message.find("line 2") != std::string::npos, "long output failure mentions line");
}

void testExamplesEnergyPrefix(Reporter& test)
{
	TempDir temp("helix-example-prefix-");
	const auto actual = temp.path() / "actual.txt";

	writeText(actual, "0 6.3499999\n0.1 6.3482833\n0.2 6.343812\n");

	const auto result = compareEnergyTracePrefix(HELIX_EXAMPLE_ENERGY_PATH, actual, 1.0e-5);

	test.expect(result.ok, "examples/outputEnergy prefix succeeds");
	test.expect(result.diff.compared_rows == 3, "examples prefix reports compared rows");
}

} // namespace

int main()
{
	Reporter test;

	testMatchingSyntheticPrefix(test);
	testEnergyToleranceFailureMessage(test);
	testTimeToleranceFailure(test);
	testEmptyActualFails(test);
	testActualLongerThanReferenceFails(test);
	testExamplesEnergyPrefix(test);

	return test.finish("energy trace comparator tests");
}
