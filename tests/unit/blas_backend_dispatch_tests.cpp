#include "backend/blas_backend.h"
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

	std::vector<backend::AxpyArgs<Scalar>> axpyCalls;
	std::vector<backend::ScalArgs<Scalar>> scalCalls;
	backend::BlasStatus next{};

	backend::BlasStatus axpy(const backend::AxpyArgs<Scalar>& args)
	{
		axpyCalls.push_back(args);
		return next;
	}

	backend::BlasStatus scal(const backend::ScalArgs<Scalar>& args)
	{
		scalCalls.push_back(args);
		return next;
	}
};

std::string captureFailureReport(const backend::BlasStatus& status)
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

	backend::reportBlasFailure(status);
	std::fflush(stdout);
	::dup2(savedDescriptor, stdoutDescriptor);
	::close(savedDescriptor);

	std::rewind(capture);
	char buffer[64] = {};
	const std::size_t bytesRead = std::fread(buffer, 1, sizeof(buffer), capture);
	std::fclose(capture);
	return std::string(buffer, bytesRead);
}

void test_axpy_dispatch_forwards_all_fields(helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar alpha{1.0f, 2.0f};
	MockBackend::Scalar x[6]{};
	MockBackend::Scalar y[6]{};

	backend::AxpyArgs<MockBackend::Scalar> args;
	args.n = 6;
	args.alpha = &alpha;
	args.x = x;
	args.incx = 2;
	args.y = y;
	args.incy = 3;

	const backend::BlasStatus status = backend::axpy(mock, args);

	reporter.expect(status.ok, "successful backend status is propagated");
	reporter.expect(mock.axpyCalls.size() == 1, "one axpy dispatch records one backend call");
	if(mock.axpyCalls.empty())
	{
		return;
	}

	const auto& seen = mock.axpyCalls.front();
	reporter.expect(seen.n == args.n, "n is forwarded");
	reporter.expect(seen.alpha == args.alpha, "alpha pointer is forwarded");
	reporter.expect(seen.x == args.x, "x pointer is forwarded");
	reporter.expect(seen.incx == args.incx, "incx is forwarded");
	reporter.expect(seen.y == args.y, "y pointer is forwarded");
	reporter.expect(seen.incy == args.incy, "incy is forwarded");
}

void test_scal_dispatch_forwards_all_fields(helix::test::Reporter& reporter)
{
	MockBackend mock;
	MockBackend::Scalar alpha{5.0f, 6.0f};
	MockBackend::Scalar x[4]{};

	backend::ScalArgs<MockBackend::Scalar> args;
	args.n = 4;
	args.alpha = &alpha;
	args.x = x;
	args.incx = 1;

	const backend::BlasStatus status = backend::scal(mock, args);

	reporter.expect(status.ok, "successful backend status is propagated");
	reporter.expect(mock.scalCalls.size() == 1, "one scal dispatch records one backend call");
	if(mock.scalCalls.empty())
	{
		return;
	}

	const auto& seen = mock.scalCalls.front();
	reporter.expect(seen.n == args.n, "n is forwarded");
	reporter.expect(seen.alpha == args.alpha, "alpha pointer is forwarded");
	reporter.expect(seen.x == args.x, "x pointer is forwarded");
	reporter.expect(seen.incx == args.incx, "incx is forwarded");
}

void test_blas_failure_status_and_diagnostic_are_preserved(helix::test::Reporter& reporter)
{
	MockBackend mock;
	mock.next = {false, 7};
	const backend::AxpyArgs<MockBackend::Scalar> axpyArgs;
	const backend::ScalArgs<MockBackend::Scalar> scalArgs;

	const backend::BlasStatus axpyStatus = backend::axpy(mock, axpyArgs);
	reporter.expect(!axpyStatus.ok, "axpy backend failure remains a failure");
	reporter.expect(axpyStatus.nativeCode == 7, "axpy native failure code is propagated");

	const backend::BlasStatus scalStatus = backend::scal(mock, scalArgs);
	reporter.expect(!scalStatus.ok, "scal backend failure remains a failure");
	reporter.expect(scalStatus.nativeCode == 7, "scal native failure code is propagated");

	const std::string diagnostic = captureFailureReport(axpyStatus);
	reporter.expect(diagnostic == "7", "failure report prints the native code with decimal formatting");

	backend::axpy(mock, axpyArgs);
	reporter.expect(mock.axpyCalls.size() == 2, "dispatch remains usable after reporting a backend failure");
}

void test_blas_dispatch_records_each_call(helix::test::Reporter& reporter)
{
	MockBackend mock;
	const backend::AxpyArgs<MockBackend::Scalar> axpyArgs;
	const backend::ScalArgs<MockBackend::Scalar> scalArgs;

	backend::axpy(mock, axpyArgs);
	backend::scal(mock, scalArgs);
	backend::axpy(mock, axpyArgs);

	reporter.expect(mock.axpyCalls.size() == 2, "two axpy dispatches record exactly two backend calls");
	reporter.expect(mock.scalCalls.size() == 1, "one scal dispatch records exactly one backend call");
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_axpy_dispatch_forwards_all_fields(reporter);
	test_scal_dispatch_forwards_all_fields(reporter);
	test_blas_failure_status_and_diagnostic_are_preserved(reporter);
	test_blas_dispatch_records_each_call(reporter);

	return reporter.finish("blas_backend_dispatch_tests");
}
