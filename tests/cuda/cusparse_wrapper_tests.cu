#include "cuda_types.h"
#include "support/assert.h"

#include <cuda_runtime.h>
#include <cusparse_v2.h>
#include <sstream>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

namespace {

#ifdef SINGLE
constexpr double kWrapperTolerance = 1.0e-5;
#else
constexpr double kWrapperTolerance = 1.0e-12;
#endif

double realPart(const Complex& value)
{
	return value.x;
}

double imagPart(const Complex& value)
{
	return value.y;
}

std::string complexMismatchMessage(int index, const Complex& expected, const Complex& actual)
{
	std::ostringstream message;
	message << "cuSPARSE wrapper mismatch at index " << index << ": expected=("
			<< realPart(expected) << "," << imagPart(expected) << ") actual=("
			<< realPart(actual) << "," << imagPart(actual) << ")";
	return message.str();
}

bool nearComplex(const Complex& lhs, const Complex& rhs)
{
	return helix::test::near(realPart(lhs), realPart(rhs), kWrapperTolerance)
		&& helix::test::near(imagPart(lhs), imagPart(rhs), kWrapperTolerance);
}

void expectComplexVectorNear(
	helix::test::Reporter& test,
	const thrust::host_vector<Complex>& actual,
	const thrust::host_vector<Complex>& expected)
{
	test.expect(actual.size() == expected.size(), "cuSPARSE wrapper output size matches reference");
	for(size_t i = 0; i < expected.size() && i < actual.size(); i++)
	{
		if(!nearComplex(expected[i], actual[i]))
		{
			test.expect(false, complexMismatchMessage(static_cast<int>(i), expected[i], actual[i]));
			return;
		}
	}
}

struct CusparseContext {
	CusparseContext(helix::test::Reporter& test)
	{
		test.expect(cusparseCreate(&handle) == CUSPARSE_STATUS_SUCCESS, "creates cuSPARSE handle");
		test.expect(
			cusparseCreateMatDescr(&descriptor) == CUSPARSE_STATUS_SUCCESS,
			"creates cuSPARSE matrix descriptor");
		cusparseSetMatType(descriptor, CUSPARSE_MATRIX_TYPE_GENERAL);
		cusparseSetMatIndexBase(descriptor, CUSPARSE_INDEX_BASE_ZERO);
	}

	~CusparseContext()
	{
		if(descriptor != nullptr)
		{
			cusparseDestroyMatDescr(descriptor);
		}
		if(handle != nullptr)
		{
			cusparseDestroy(handle);
		}
	}

	cusparseHandle_t handle = nullptr;
	cusparseMatDescr_t descriptor = nullptr;
};

void testCsrmmNonTranspose(helix::test::Reporter& test)
{
	CusparseContext context(test);

	const thrust::host_vector<int> rowOffsets{0, 2, 4};
	const thrust::host_vector<int> columns{0, 1, 1, 2};
	const thrust::host_vector<Complex> values{
		make_Complex(1.0, 0.0),
		make_Complex(2.0, 0.0),
		make_Complex(3.0, 0.0),
		make_Complex(4.0, 0.0),
	};
	const thrust::host_vector<Complex> denseB{
		make_Complex(5.0, 0.0),
		make_Complex(7.0, 0.0),
		make_Complex(9.0, 0.0),
		make_Complex(6.0, 0.0),
		make_Complex(8.0, 0.0),
		make_Complex(10.0, 0.0),
	};
	const thrust::host_vector<Complex> expected{
		make_Complex(19.0, 0.0),
		make_Complex(57.0, 0.0),
		make_Complex(22.0, 0.0),
		make_Complex(64.0, 0.0),
	};

	thrust::device_vector<int> dRowOffsets = rowOffsets;
	thrust::device_vector<int> dColumns = columns;
	thrust::device_vector<Complex> dValues = values;
	thrust::device_vector<Complex> dDenseB = denseB;
	thrust::device_vector<Complex> dDenseC(4, make_Complex(-1.0, 0.0));
	const Complex alpha = make_Complex(1.0, 0.0);
	const Complex beta = make_Complex(0.0, 0.0);

	const cusparseStatus_t status = cusparseCsrmm(
		context.handle,
		CUSPARSE_OPERATION_NON_TRANSPOSE,
		2,
		2,
		3,
		static_cast<int>(values.size()),
		&alpha,
		context.descriptor,
		thrust::raw_pointer_cast(dValues.data()),
		thrust::raw_pointer_cast(dRowOffsets.data()),
		thrust::raw_pointer_cast(dColumns.data()),
		thrust::raw_pointer_cast(dDenseB.data()),
		3,
		&beta,
		thrust::raw_pointer_cast(dDenseC.data()),
		2);

	test.expect(status == CUSPARSE_STATUS_SUCCESS, "cusparseCsrmm non-transpose wrapper succeeds");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "cusparseCsrmm non-transpose work completes");

	const thrust::host_vector<Complex> actual = dDenseC;
	expectComplexVectorNear(test, actual, expected);
}

void testCsrmm2TransposeB(helix::test::Reporter& test)
{
	CusparseContext context(test);

	const thrust::host_vector<int> rowOffsets{0, 2, 4};
	const thrust::host_vector<int> columns{0, 1, 1, 2};
	const thrust::host_vector<Complex> values{
		make_Complex(1.0, 0.0),
		make_Complex(2.0, 0.0),
		make_Complex(3.0, 0.0),
		make_Complex(4.0, 0.0),
	};
	const thrust::host_vector<Complex> denseBTransposedStorage{
		make_Complex(5.0, 0.0),
		make_Complex(6.0, 0.0),
		make_Complex(7.0, 0.0),
		make_Complex(8.0, 0.0),
		make_Complex(9.0, 0.0),
		make_Complex(10.0, 0.0),
	};
	const thrust::host_vector<Complex> expected{
		make_Complex(19.0, 0.0),
		make_Complex(57.0, 0.0),
		make_Complex(22.0, 0.0),
		make_Complex(64.0, 0.0),
	};

	thrust::device_vector<int> dRowOffsets = rowOffsets;
	thrust::device_vector<int> dColumns = columns;
	thrust::device_vector<Complex> dValues = values;
	thrust::device_vector<Complex> dDenseB = denseBTransposedStorage;
	thrust::device_vector<Complex> dDenseC(4, make_Complex(0.0, 0.0));
	const Complex alpha = make_Complex(1.0, 0.0);
	const Complex beta = make_Complex(0.0, 0.0);

	const cusparseStatus_t status = cusparseCsrmm2(
		context.handle,
		CUSPARSE_OPERATION_NON_TRANSPOSE,
		CUSPARSE_OPERATION_TRANSPOSE,
		2,
		2,
		3,
		static_cast<int>(values.size()),
		&alpha,
		context.descriptor,
		thrust::raw_pointer_cast(dValues.data()),
		thrust::raw_pointer_cast(dRowOffsets.data()),
		thrust::raw_pointer_cast(dColumns.data()),
		thrust::raw_pointer_cast(dDenseB.data()),
		2,
		&beta,
		thrust::raw_pointer_cast(dDenseC.data()),
		2);

	test.expect(status == CUSPARSE_STATUS_SUCCESS, "cusparseCsrmm2 transposed-B wrapper succeeds");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "cusparseCsrmm2 transposed-B work completes");

	const thrust::host_vector<Complex> actual = dDenseC;
	expectComplexVectorNear(test, actual, expected);
}

void testCsrmmReportsInvalidHandle(helix::test::Reporter& test)
{
	CusparseContext context(test);

	const thrust::host_vector<int> rowOffsets{0, 1};
	const thrust::host_vector<int> columns{0};
	const thrust::host_vector<Complex> values{make_Complex(1.0, 0.0)};
	const thrust::host_vector<Complex> denseB{make_Complex(2.0, 0.0)};

	thrust::device_vector<int> dRowOffsets = rowOffsets;
	thrust::device_vector<int> dColumns = columns;
	thrust::device_vector<Complex> dValues = values;
	thrust::device_vector<Complex> dDenseB = denseB;
	thrust::device_vector<Complex> dDenseC(1, make_Complex(0.0, 0.0));
	const Complex alpha = make_Complex(1.0, 0.0);
	const Complex beta = make_Complex(0.0, 0.0);

	const cusparseStatus_t status = cusparseCsrmm(
		nullptr,
		CUSPARSE_OPERATION_NON_TRANSPOSE,
		1,
		1,
		1,
		static_cast<int>(values.size()),
		&alpha,
		context.descriptor,
		thrust::raw_pointer_cast(dValues.data()),
		thrust::raw_pointer_cast(dRowOffsets.data()),
		thrust::raw_pointer_cast(dColumns.data()),
		thrust::raw_pointer_cast(dDenseB.data()),
		1,
		&beta,
		thrust::raw_pointer_cast(dDenseC.data()),
		1);

	test.expect(status != CUSPARSE_STATUS_SUCCESS, "cusparseCsrmm wrapper reports invalid handle failure");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testCsrmmNonTranspose(test);
	testCsrmm2TransposeB(test);
	testCsrmmReportsInvalidHandle(test);

	return test.finish("cuSPARSE wrapper CUDA tests");
}
