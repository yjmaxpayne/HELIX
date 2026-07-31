#include "backend/transpose_backend.h"
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

	std::vector<backend::TransposeArgs<Scalar>> calls;
	backend::TransposeStatus next{};

	backend::TransposeStatus transpose(const backend::TransposeArgs<Scalar>& args)
	{
		calls.push_back(args);
		return next;
	}
};

std::string captureFailureReport(const backend::TransposeStatus& status)
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

	backend::reportTransposeFailure(status);
	std::fflush(stdout);
	::dup2(savedDescriptor, stdoutDescriptor);
	::close(savedDescriptor);

	std::rewind(capture);
	char buffer[64] = {};
	const std::size_t bytesRead = std::fread(buffer, 1, sizeof(buffer), capture);
	std::fclose(capture);
	return std::string(buffer, bytesRead);
}

void test_transpose_dispatch_forwards_all_fields(helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar data{};

	backend::TransposeArgs<MockBackend::Scalar> args;
	args.data = &data;
	args.n = 64;

	const backend::TransposeStatus status = backend::transpose(mock, args);

	reporter.expect(status.ok, "successful backend status is propagated");
	reporter.expect(mock.calls.size() == 1, "one dispatch records one backend call");
	if(mock.calls.empty())
	{
		return;
	}

	const auto& seen = mock.calls.front();
	reporter.expect(seen.data == args.data, "data pointer is forwarded");
	reporter.expect(seen.n == args.n, "n is forwarded");
}

void test_transpose_failure_status_and_diagnostic_are_preserved(helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar data{};
	mock.next = {false, 17};

	backend::TransposeArgs<MockBackend::Scalar> args;
	args.data = &data;
	args.n = 64;

	const backend::TransposeStatus status = backend::transpose(mock, args);
	reporter.expect(!status.ok, "backend failure remains a failure");
	reporter.expect(status.nativeCode == 17, "backend native failure code is propagated");

	const std::string diagnostic = captureFailureReport(status);
	reporter.expect(diagnostic == "17", "failure report prints the native code with decimal formatting");

	backend::transpose(mock, args);
	reporter.expect(mock.calls.size() == 2, "dispatch remains usable after reporting a backend failure");
}

void test_transpose_dispatch_records_each_call(helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar data{};

	backend::TransposeArgs<MockBackend::Scalar> args;
	args.data = &data;
	args.n = 32;

	backend::transpose(mock, args);
	backend::transpose(mock, args);
	backend::transpose(mock, args);

	reporter.expect(mock.calls.size() == 3, "three dispatches record exactly three backend calls");
}

void test_transpose_dispatch_rejects_invalid_arguments_without_calling_backend(
	helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar data{};

	backend::TransposeArgs<MockBackend::Scalar> tileViolation;
	tileViolation.data = &data;
	tileViolation.n = 33;
	const backend::TransposeStatus tileStatus = backend::transpose(mock, tileViolation);
	reporter.expect(!tileStatus.ok, "an unsupported tile size is rejected");
	reporter.expect(tileStatus.nativeCode == backend::kTransposeTileConstraintViolation,
		"an unsupported tile size reports the tile constraint diagnostic");

	backend::TransposeArgs<MockBackend::Scalar> zeroSize;
	zeroSize.data = &data;
	zeroSize.n = 0;
	const backend::TransposeStatus zeroSizeStatus = backend::transpose(mock, zeroSize);
	reporter.expect(!zeroSizeStatus.ok, "a zero-sized transpose is rejected");
	reporter.expect(zeroSizeStatus.nativeCode == backend::kTransposeInvalidArguments,
		"a zero-sized transpose reports the invalid-arguments diagnostic");

	backend::TransposeArgs<MockBackend::Scalar> nullData;
	nullData.data = nullptr;
	nullData.n = 32;
	const backend::TransposeStatus nullDataStatus = backend::transpose(mock, nullData);
	reporter.expect(!nullDataStatus.ok, "a null data pointer is rejected");
	reporter.expect(nullDataStatus.nativeCode == backend::kTransposeInvalidArguments,
		"a null data pointer reports the invalid-arguments diagnostic");

	reporter.expect(mock.calls.empty(), "invalid arguments never reach the backend");
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_transpose_dispatch_forwards_all_fields(reporter);
	test_transpose_failure_status_and_diagnostic_are_preserved(reporter);
	test_transpose_dispatch_records_each_call(reporter);
	test_transpose_dispatch_rejects_invalid_arguments_without_calling_backend(reporter);

	return reporter.finish("transpose_backend_dispatch_tests");
}
