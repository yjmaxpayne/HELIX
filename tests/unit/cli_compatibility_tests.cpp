#include "cli_compatibility.h"
#include "support/assert.h"

#include <climits>
#include <sstream>
#include <string>

namespace {

using helix::cli::StepCountInputs;

int readWithWarnings(const StepCountInputs& inputs, std::string& warnings)
{
	std::ostringstream output;
	const int steps = helix::cli::readStepCount(inputs, output);
	warnings = output.str();
	return steps;
}

void testHelixStepsTakesPriority(helix::test::Reporter& test)
{
	StepCountInputs inputs;
	inputs.helixSteps = "7";
	inputs.heomSteps = "9";
	inputs.defaultStepCount = 42;

	std::string warnings;
	const int steps = readWithWarnings(inputs, warnings);

	test.expect(steps == 7, "HELIX_STEPS takes priority over HEOM_STEPS");
	test.expect(warnings.empty(), "valid HELIX_STEPS emits no warning");
}

void testHeomStepsAliasWhenPrimaryMissing(helix::test::Reporter& test)
{
	StepCountInputs inputs;
	inputs.heomSteps = "11";
	inputs.defaultStepCount = 42;

	std::string warnings;
	const int steps = readWithWarnings(inputs, warnings);

	test.expect(steps == 11, "HEOM_STEPS remains a compatibility alias");
	test.expect(warnings.empty(), "valid HEOM_STEPS emits no warning");
}

void testEmptyPrimaryFallsBackToAlias(helix::test::Reporter& test)
{
	StepCountInputs inputs;
	inputs.helixSteps = "";
	inputs.heomSteps = "13";
	inputs.defaultStepCount = 42;

	std::string warnings;
	const int steps = readWithWarnings(inputs, warnings);

	test.expect(steps == 13, "empty HELIX_STEPS falls back to HEOM_STEPS");
	test.expect(warnings.empty(), "valid alias after empty primary emits no warning");
}

void testInvalidPrimaryFallsBackToDefault(helix::test::Reporter& test)
{
	StepCountInputs inputs;
	inputs.helixSteps = "bad";
	inputs.heomSteps = "17";
	inputs.defaultStepCount = 42;

	std::string warnings;
	const int steps = readWithWarnings(inputs, warnings);

	test.expect(steps == 42, "invalid HELIX_STEPS falls back to the default step count");
	test.expect(warnings.find("Ignoring invalid HELIX_STEPS=bad") != std::string::npos,
		"invalid primary warning names HELIX_STEPS");
}

void testNegativeAndTooLargeValuesFallback(helix::test::Reporter& test)
{
	StepCountInputs negative;
	negative.helixSteps = "-1";
	negative.defaultStepCount = 42;

	std::string warnings;
	test.expect(readWithWarnings(negative, warnings) == 42, "negative step counts fall back");
	test.expect(warnings.find("HELIX_STEPS=-1") != std::string::npos, "negative warning includes value");

	StepCountInputs tooLarge;
	tooLarge.heomSteps = "2147483648";
	tooLarge.defaultStepCount = 42;

	test.expect(readWithWarnings(tooLarge, warnings) == 42, "step counts larger than INT_MAX fall back");
	test.expect(warnings.find("HEOM_STEPS=2147483648") != std::string::npos,
		"overflow warning names HEOM_STEPS");
}

void testMissingValuesUseDefaultWithoutWarning(helix::test::Reporter& test)
{
	StepCountInputs inputs;
	inputs.defaultStepCount = 42;

	std::string warnings;
	const int steps = readWithWarnings(inputs, warnings);

	test.expect(steps == 42, "missing step env vars use the default step count");
	test.expect(warnings.empty(), "missing step env vars emit no warning");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testHelixStepsTakesPriority(test);
	testHeomStepsAliasWhenPrimaryMissing(test);
	testEmptyPrimaryFallsBackToAlias(test);
	testInvalidPrimaryFallsBackToDefault(test);
	testNegativeAndTooLargeValuesFallback(test);
	testMissingValuesUseDefaultWithoutWarning(test);

	return test.finish("cli compatibility tests");
}
