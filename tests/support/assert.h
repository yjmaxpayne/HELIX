#pragma once

#include "tolerance.h"
#include <iostream>
#include <string>

namespace helix::test {

class Reporter {
public:
	explicit Reporter(std::ostream& output = std::cout, std::ostream& error = std::cerr)
		: output_(output), error_(error)
	{
	}

	void expect(bool condition, const char* message)
	{
		if(!condition)
		{
			fail(message);
		}
	}

	void expect(bool condition, const std::string& message)
	{
		expect(condition, message.c_str());
	}

	void expectNear(double lhs, double rhs, double tolerance, const char* message)
	{
		expect(near(lhs, rhs, tolerance), message);
	}

	int failures() const
	{
		return failures_;
	}

	int finish(const char* suiteName) const
	{
		if(failures_ != 0)
		{
			error_ << "FAIL: " << suiteName << " (" << failures_ << " failure(s))" << std::endl;
			return 1;
		}

		output_ << "PASS: " << suiteName << std::endl;
		return 0;
	}

private:
	void fail(const char* message)
	{
		error_ << "FAIL: " << message << std::endl;
		failures_++;
	}

	std::ostream& output_;
	std::ostream& error_;
	int failures_ = 0;
};

} // namespace helix::test
