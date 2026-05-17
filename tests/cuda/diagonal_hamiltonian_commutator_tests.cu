#include "liouville.h"
#include "support/assert.h"

#include <cuda_runtime.h>
#include <sstream>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

namespace {

#ifdef SINGLE
constexpr double kTolerance = 1.0e-5;
#else
constexpr double kTolerance = 1.0e-12;
#endif

struct HostComplex
{
	double real = 0.0;
	double imag = 0.0;
};

double realPart(const Complex& value)
{
	return value.x;
}

double imagPart(const Complex& value)
{
	return value.y;
}

HostComplex toHostComplex(const Complex& value)
{
	return {realPart(value), imagPart(value)};
}

HostComplex add(HostComplex lhs, HostComplex rhs)
{
	return {lhs.real + rhs.real, lhs.imag + rhs.imag};
}

HostComplex multiply(HostComplex lhs, HostComplex rhs)
{
	return {
		lhs.real * rhs.real - lhs.imag * rhs.imag,
		lhs.real * rhs.imag + lhs.imag * rhs.real
	};
}

Complex toDeviceComplex(HostComplex value)
{
	return make_Complex(value.real, value.imag);
}

bool nearComplex(const Complex& lhs, const Complex& rhs)
{
	return helix::test::near(realPart(lhs), realPart(rhs), kTolerance)
		&& helix::test::near(imagPart(lhs), imagPart(rhs), kTolerance);
}

std::string mismatchMessage(int n, int row, int column, const Complex& expected, const Complex& actual)
{
	std::ostringstream message;
	message << "diagonal H commutator mismatch n=" << n << " row=" << row
			<< " column=" << column << ": expected=(" << realPart(expected) << ","
			<< imagPart(expected) << ") actual=(" << realPart(actual) << ","
			<< imagPart(actual) << ")";
	return message.str();
}

Complex rhoValue(int row, int column)
{
	return make_Complex(
		0.25 + row * 0.37 - column * 0.11,
		-0.5 + row * 0.07 + column * 0.19);
}

Complex diagonalValue(int index)
{
	if(index == 2)
	{
		return diagonalValue(1);
	}
	return make_Complex(-1.25 + index * 0.83, 0.0);
}

Complex hostReference(const thrust::host_vector<Complex>& diagonal,
	const thrust::host_vector<Complex>& rho,
	int n,
	int row,
	int column)
{
	const HostComplex minusI{0.0, -1.0};
	const HostComplex plusI{0.0, 1.0};
	const HostComplex rhoElement = toHostComplex(rho[row * n + column]);
	const HostComplex left = multiply(toHostComplex(diagonal[row]), rhoElement);
	const HostComplex right = multiply(rhoElement, toHostComplex(diagonal[column]));
	return toDeviceComplex(add(multiply(minusI, left), multiply(plusI, right)));
}

void runReferenceCase(helix::test::Reporter& test, int n)
{
	thrust::host_vector<Complex> diagonal(n);
	thrust::host_vector<Complex> rho(n * n);
	thrust::host_vector<Complex> expected(n * n);

	for(int index = 0; index < n; index++)
	{
		diagonal[index] = diagonalValue(index);
	}

	for(int row = 0; row < n; row++)
	{
		for(int column = 0; column < n; column++)
		{
			const int offset = row * n + column;
			rho[offset] = rhoValue(row, column);
			expected[offset] = hostReference(diagonal, rho, n, row, column);
		}
	}

	thrust::device_vector<Complex> dDiagonal = diagonal;
	thrust::device_vector<Complex> dRho = rho;
	thrust::device_vector<Complex> dResult(n * n, make_Complex(99.0, -99.0));
	cudaStream_t stream = nullptr;

	test.expect(cudaStreamCreate(&stream) == cudaSuccess, "creates stream for diagonal H test");
	addDiagonalHamiltonianCommutator(
		thrust::raw_pointer_cast(dDiagonal.data()),
		thrust::raw_pointer_cast(dRho.data()),
		n,
		thrust::raw_pointer_cast(dResult.data()),
		stream);
	test.expect(cudaStreamSynchronize(stream) == cudaSuccess, "diagonal H commutator kernel completes");

	const thrust::host_vector<Complex> actual = dResult;
	for(int row = 0; row < n; row++)
	{
		for(int column = 0; column < n; column++)
		{
			const int offset = row * n + column;
			if(!nearComplex(expected[offset], actual[offset]))
			{
				test.expect(false, mismatchMessage(n, row, column, expected[offset], actual[offset]));
				cudaStreamDestroy(stream);
				return;
			}
		}
	}
	test.expect(nearComplex(make_Complex(0.0, 0.0), actual[0]),
		"diagonal H commutator produces zero on matrix diagonal");
	if(n > 2)
	{
		test.expect(nearComplex(make_Complex(0.0, 0.0), actual[1 * n + 2]),
			"diagonal H commutator produces zero for degenerate energy pairs");
	}

	cudaStreamDestroy(stream);
}

} // namespace

int main()
{
	helix::test::Reporter test;

	runReferenceCase(test, 4);
	runReferenceCase(test, 8);

	return test.finish("diagonal Hamiltonian commutator CUDA tests");
}
