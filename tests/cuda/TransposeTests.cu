#include "MatrixUtil.h"
#include "support/Assert.h"

#include <cuda_runtime.h>
#include <sstream>
#include <vector>

namespace {

constexpr int kMatrixSize = 64;
constexpr int kTileDim = 32;
constexpr double kTolerance = 1.0e-6;

double realPart(const Complex& value)
{
	return value.x;
}

double imagPart(const Complex& value)
{
	return value.y;
}

Complex makeValue(int row, int column)
{
	return make_Complex(row * 1000 + column, column * 1000 + row);
}

std::string mismatchMessage(int index, const Complex& expected, const Complex& actual)
{
	std::ostringstream message;
	message << "transpose mismatch at index " << index << ": expected=(" << realPart(expected)
			<< "," << imagPart(expected) << ") actual=(" << realPart(actual) << ","
			<< imagPart(actual) << ")";
	return message.str();
}

bool nearComplex(const Complex& lhs, const Complex& rhs)
{
	return helix::test::near(realPart(lhs), realPart(rhs), kTolerance)
		&& helix::test::near(imagPart(lhs), imagPart(rhs), kTolerance);
}

void testDeviceTranspose64x64(helix::test::Reporter& test)
{
	static_assert(kMatrixSize % kTileDim == 0, "MatrixUtil::transpose requires TILE_DIM multiples");

	std::vector<Complex> input(kMatrixSize * kMatrixSize);
	for(int row = 0; row < kMatrixSize; row++)
	{
		for(int column = 0; column < kMatrixSize; column++)
		{
			input[column + row * kMatrixSize] = makeValue(row, column);
		}
	}

	Complex* deviceMatrix = nullptr;
	cudaStream_t stream = nullptr;
	const std::size_t byteCount = input.size() * sizeof(Complex);

	test.expect(cudaStreamCreate(&stream) == cudaSuccess, "creates CUDA stream for transpose test");
	test.expect(cudaMalloc(&deviceMatrix, byteCount) == cudaSuccess, "allocates device matrix");
	test.expect(
		cudaMemcpy(deviceMatrix, input.data(), byteCount, cudaMemcpyHostToDevice) == cudaSuccess,
		"copies transpose input to device");

	transpose(deviceMatrix, kMatrixSize, stream);
	test.expect(cudaStreamSynchronize(stream) == cudaSuccess, "device transpose completes");

	std::vector<Complex> actual(input.size());
	test.expect(
		cudaMemcpy(actual.data(), deviceMatrix, byteCount, cudaMemcpyDeviceToHost) == cudaSuccess,
		"copies transpose output to host");

	for(int row = 0; row < kMatrixSize; row++)
	{
		for(int column = 0; column < kMatrixSize; column++)
		{
			const int index = column + row * kMatrixSize;
			const Complex expected = input[row + column * kMatrixSize];
			if(!nearComplex(expected, actual[index]))
			{
				test.expect(false, mismatchMessage(index, expected, actual[index]));
				cudaFree(deviceMatrix);
				cudaStreamDestroy(stream);
				return;
			}
		}
	}

	cudaFree(deviceMatrix);
	cudaStreamDestroy(stream);
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testDeviceTranspose64x64(test);

	return test.finish("transpose CUDA tests");
}
