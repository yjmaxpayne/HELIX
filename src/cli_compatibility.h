#pragma once

#include <climits>
#include <cstdlib>
#include <ostream>

namespace helix::cli {

struct StepCountInputs {
	const char* helixSteps = nullptr;
	const char* heomSteps = nullptr;
	int defaultStepCount = 1000000;
};

inline bool hasStepCountValue(const char* value)
{
	return value != nullptr && value[0] != '\0';
}

inline int readStepCount(const StepCountInputs& inputs, std::ostream& warnings)
{
	const char* envName = nullptr;
	const char* value = nullptr;
	if(hasStepCountValue(inputs.helixSteps))
	{
		envName = "HELIX_STEPS";
		value = inputs.helixSteps;
	}
	else if(hasStepCountValue(inputs.heomSteps))
	{
		envName = "HEOM_STEPS";
		value = inputs.heomSteps;
	}
	else
	{
		return inputs.defaultStepCount;
	}

	char* end = nullptr;
	const long parsed = std::strtol(value, &end, 10);
	if(*end != '\0' || parsed < 0 || parsed > INT_MAX)
	{
		warnings << "Ignoring invalid " << envName << "=" << value << '\n';
		return inputs.defaultStepCount;
	}
	return static_cast<int>(parsed);
}

int readStepCount();
int runCompatibilityCli(int argc, char** argv);

} // namespace helix::cli
