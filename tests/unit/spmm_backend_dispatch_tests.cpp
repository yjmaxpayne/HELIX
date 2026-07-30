#include "backend/spmm_backend.h"
#include "support/assert.h"

#include <complex>
#include <cstdio>
#include <string>
#include <unistd.h>
#include <vector>

namespace {

namespace backend = helix::backend;

struct MockBackend
{
	using Scalar = std::complex<float>;

	std::vector<backend::SpmmArgs<Scalar>> calls;
	backend::SpmmStatus next{};

	backend::SpmmStatus spmm(const backend::SpmmArgs<Scalar>& args)
	{
		calls.push_back(args);
		return next;
	}
};

std::string captureFailureReport(const backend::SpmmStatus& status)
{
	std::fflush(stdout);
	FILE* capture = std::tmpfile();
	if(capture == nullptr)
	{
		return {};
	}

	const int stdoutDescriptor = ::fileno(stdout);
	const int savedDescriptor = ::dup(stdoutDescriptor);
	if(savedDescriptor < 0 || ::dup2(::fileno(capture), stdoutDescriptor) < 0)
	{
		if(savedDescriptor >= 0)
		{
			::close(savedDescriptor);
		}
		std::fclose(capture);
		return {};
	}

	backend::reportSpmmFailure(status);
	std::fflush(stdout);
	::dup2(savedDescriptor, stdoutDescriptor);
	::close(savedDescriptor);

	std::rewind(capture);
	char buffer[64] = {};
	const std::size_t bytesRead = std::fread(buffer, 1, sizeof(buffer), capture);
	std::fclose(capture);
	return std::string(buffer, bytesRead);
}

void test_spmm_dispatch_forwards_all_fields(helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar alpha{1.0f, 2.0f};
	MockBackend::Scalar beta{3.0f, 4.0f};
	MockBackend::Scalar csrValues[2]{};
	int csrRowOffsets[3]{};
	int csrColumns[2]{};
	MockBackend::Scalar denseInput[20]{};
	MockBackend::Scalar denseOutput[12]{};

	backend::SpmmArgs<MockBackend::Scalar> args;
	args.transB = backend::SpmmOperation::Transpose;
	args.m = 3;
	args.n = 4;
	args.k = 5;
	args.nnz = 2;
	args.alpha = &alpha;
	args.csrValues = csrValues;
	args.csrRowOffsets = csrRowOffsets;
	args.csrColumns = csrColumns;
	args.denseInput = denseInput;
	args.ldb = 5;
	args.beta = &beta;
	args.denseOutput = denseOutput;
	args.ldc = 3;

	const backend::SpmmStatus status = backend::spmm(mock, args);

	reporter.expect(status.ok, "successful backend status is propagated");
	reporter.expect(mock.calls.size() == 1, "one dispatch records one backend call");
	if(mock.calls.empty())
	{
		return;
	}

	const auto& seen = mock.calls.front();
	reporter.expect(seen.transB == args.transB, "transB is forwarded");
	reporter.expect(seen.m == args.m, "m is forwarded");
	reporter.expect(seen.n == args.n, "n is forwarded");
	reporter.expect(seen.k == args.k, "k is forwarded");
	reporter.expect(seen.nnz == args.nnz, "nnz is forwarded");
	reporter.expect(seen.alpha == args.alpha, "alpha pointer is forwarded");
	reporter.expect(seen.csrValues == args.csrValues, "CSR values pointer is forwarded");
	reporter.expect(seen.csrRowOffsets == args.csrRowOffsets, "CSR row offsets pointer is forwarded");
	reporter.expect(seen.csrColumns == args.csrColumns, "CSR columns pointer is forwarded");
	reporter.expect(seen.denseInput == args.denseInput, "dense input pointer is forwarded");
	reporter.expect(seen.ldb == args.ldb, "ldb is forwarded");
	reporter.expect(seen.beta == args.beta, "beta pointer is forwarded");
	reporter.expect(seen.denseOutput == args.denseOutput, "dense output pointer is forwarded");
	reporter.expect(seen.ldc == args.ldc, "ldc is forwarded");
}

void test_spmm_failure_status_and_diagnostic_are_preserved(helix::test::Reporter& reporter)
{
	MockBackend mock;
	mock.next = {false, 3};
	const backend::SpmmArgs<MockBackend::Scalar> args;

	const backend::SpmmStatus status = backend::spmm(mock, args);
	reporter.expect(!status.ok, "backend failure remains a failure");
	reporter.expect(status.nativeCode == 3, "backend native failure code is propagated");

	const std::string diagnostic = captureFailureReport(status);
	reporter.expect(diagnostic == "3", "failure report prints the native code with decimal formatting");

	backend::spmm(mock, args);
	reporter.expect(mock.calls.size() == 2, "dispatch remains usable after reporting a backend failure");
}

void test_spmm_dispatch_records_each_call(helix::test::Reporter& reporter)
{
	MockBackend mock;
	const backend::SpmmArgs<MockBackend::Scalar> args;

	backend::spmm(mock, args);
	backend::spmm(mock, args);
	backend::spmm(mock, args);

	reporter.expect(mock.calls.size() == 3, "three dispatches record exactly three backend calls");
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_spmm_dispatch_forwards_all_fields(reporter);
	test_spmm_failure_status_and_diagnostic_are_preserved(reporter);
	test_spmm_dispatch_records_each_call(reporter);

	return reporter.finish("spmm_backend_dispatch_tests");
}
