#include "cuda_types.h"
#include "cuda_sparse_backend_plan.h"
#include "library/backend_profiling.h"
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

struct PlanInputs {
	thrust::device_vector<int> rowOffsets;
	thrust::device_vector<int> columns;
	thrust::device_vector<Complex> values;
	thrust::device_vector<Complex> denseB;
	thrust::device_vector<Complex> denseC;
};

PlanInputs makePlanInputs()
{
	PlanInputs inputs;
	inputs.rowOffsets = thrust::host_vector<int>{0, 2, 4};
	inputs.columns = thrust::host_vector<int>{0, 1, 1, 2};
	inputs.values = thrust::host_vector<Complex>{
		make_Complex(1.0, 0.0),
		make_Complex(2.0, 0.0),
		make_Complex(3.0, 0.0),
		make_Complex(4.0, 0.0),
	};
	inputs.denseB = thrust::host_vector<Complex>{
		make_Complex(5.0, 0.0),
		make_Complex(7.0, 0.0),
		make_Complex(9.0, 0.0),
		make_Complex(6.0, 0.0),
		make_Complex(8.0, 0.0),
		make_Complex(10.0, 0.0),
	};
	inputs.denseC.resize(4, make_Complex(0.0, 0.0));
	return inputs;
}

helix::cuda_backend::CudaSparseSpmmArgs makePlanArgs(
	CusparseContext& context,
	PlanInputs& inputs,
	int m = 2,
	int n = 2,
	int k = 3)
{
	static const Complex alpha = make_Complex(1.0, 0.0);
	static const Complex beta = make_Complex(0.0, 0.0);

	helix::cuda_backend::CudaSparseSpmmArgs args;
	args.handle = context.handle;
	args.stream = nullptr;
	args.transA = CUSPARSE_OPERATION_NON_TRANSPOSE;
	args.transB = CUSPARSE_OPERATION_NON_TRANSPOSE;
	args.m = m;
	args.n = n;
	args.k = k;
	args.nnz = static_cast<int>(inputs.values.size());
	args.alpha = &alpha;
	args.csrValues = thrust::raw_pointer_cast(inputs.values.data());
	args.csrRowOffsets = thrust::raw_pointer_cast(inputs.rowOffsets.data());
	args.csrColumns = thrust::raw_pointer_cast(inputs.columns.data());
	args.denseInput = thrust::raw_pointer_cast(inputs.denseB.data());
	args.ldb = 3;
	args.beta = &beta;
	args.denseOutput = thrust::raw_pointer_cast(inputs.denseC.data());
	args.ldc = 2;
	return args;
}

void testBackendPlanReusesDescriptorsAndWorkspace(helix::test::Reporter& test)
{
	CusparseContext context(test);
	PlanInputs inputs = makePlanInputs();
	helix::cuda_backend::CudaSparseBackendPlan plan;

	const thrust::host_vector<Complex> expected{
		make_Complex(19.0, 0.0),
		make_Complex(57.0, 0.0),
		make_Complex(22.0, 0.0),
		make_Complex(64.0, 0.0),
	};

	const auto firstStatus = plan.run(makePlanArgs(context, inputs));
	test.expect(firstStatus == CUSPARSE_STATUS_SUCCESS, "backend plan first SpMM succeeds");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "backend plan first SpMM completes");
	expectComplexVectorNear(test, thrust::host_vector<Complex>(inputs.denseC), expected);

	thrust::fill(inputs.denseC.begin(), inputs.denseC.end(), make_Complex(0.0, 0.0));
	const auto secondStatus = plan.run(makePlanArgs(context, inputs));
	test.expect(secondStatus == CUSPARSE_STATUS_SUCCESS, "backend plan second SpMM succeeds");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "backend plan second SpMM completes");
	expectComplexVectorNear(test, thrust::host_vector<Complex>(inputs.denseC), expected);

	test.expect(plan.spmmCallCount() == 2, "backend plan counts both SpMM calls");
	test.expect(plan.descriptorCreateCount() == 3, "backend plan creates descriptors once");
	test.expect(plan.bufferSizeQueryCount() == 1, "backend plan queries workspace once");
	test.expect(plan.workspaceHighWaterBytes() == plan.workspaceBytes(), "backend plan tracks workspace high-water");
	test.expect(plan.workspaceAllocCount() <= 1, "backend plan does not allocate workspace per call");
}

void testBackendPlanUpdatesDensePointersWithoutRecreate(helix::test::Reporter& test)
{
	CusparseContext context(test);
	PlanInputs inputs = makePlanInputs();
	helix::cuda_backend::CudaSparseBackendPlan plan;

	const thrust::host_vector<Complex> firstExpected{
		make_Complex(19.0, 0.0),
		make_Complex(57.0, 0.0),
		make_Complex(22.0, 0.0),
		make_Complex(64.0, 0.0),
	};
	const thrust::host_vector<Complex> secondDenseB{
		make_Complex(1.0, 0.0),
		make_Complex(4.0, 0.0),
		make_Complex(7.0, 0.0),
		make_Complex(2.0, 0.0),
		make_Complex(5.0, 0.0),
		make_Complex(8.0, 0.0),
	};
	const thrust::host_vector<Complex> secondExpected{
		make_Complex(9.0, 0.0),
		make_Complex(40.0, 0.0),
		make_Complex(12.0, 0.0),
		make_Complex(47.0, 0.0),
	};

	test.expect(plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
		"backend plan first dense-pointer run succeeds");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "backend plan first dense-pointer run completes");
	expectComplexVectorNear(test, thrust::host_vector<Complex>(inputs.denseC), firstExpected);

	thrust::device_vector<Complex> alternateDenseB = secondDenseB;
	thrust::device_vector<Complex> alternateDenseC(4, make_Complex(0.0, 0.0));
	auto args = makePlanArgs(context, inputs);
	args.denseInput = thrust::raw_pointer_cast(alternateDenseB.data());
	args.denseOutput = thrust::raw_pointer_cast(alternateDenseC.data());

	test.expect(plan.run(args) == CUSPARSE_STATUS_SUCCESS,
		"backend plan accepts same-shape dense pointer updates");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "backend plan dense pointer update run completes");
	expectComplexVectorNear(test, thrust::host_vector<Complex>(alternateDenseC), secondExpected);
	test.expect(plan.descriptorCreateCount() == 3,
		"dense pointer updates reuse existing sparse and dense descriptors");
	test.expect(plan.bufferSizeQueryCount() == 1,
		"dense pointer updates do not repeat SpMM buffer-size queries");
	test.expect(plan.workspaceAllocCount() <= 1,
		"dense pointer updates do not allocate a fresh workspace");
}

void testBackendPlanQueuesDensePointerUpdatesOnSameStream(helix::test::Reporter& test)
{
	CusparseContext context(test);
	PlanInputs inputs = makePlanInputs();
	helix::cuda_backend::CudaSparseBackendPlan plan;
	cudaStream_t stream = nullptr;

	const thrust::host_vector<Complex> firstExpected{
		make_Complex(19.0, 0.0),
		make_Complex(57.0, 0.0),
		make_Complex(22.0, 0.0),
		make_Complex(64.0, 0.0),
	};
	const thrust::host_vector<Complex> secondDenseB{
		make_Complex(1.0, 0.0),
		make_Complex(4.0, 0.0),
		make_Complex(7.0, 0.0),
		make_Complex(2.0, 0.0),
		make_Complex(5.0, 0.0),
		make_Complex(8.0, 0.0),
	};
	const thrust::host_vector<Complex> secondExpected{
		make_Complex(9.0, 0.0),
		make_Complex(40.0, 0.0),
		make_Complex(12.0, 0.0),
		make_Complex(47.0, 0.0),
	};

	test.expect(cudaStreamCreate(&stream) == cudaSuccess,
		"creates stream for same-stream dense pointer update test");

	auto warmupArgs = makePlanArgs(context, inputs);
	warmupArgs.stream = stream;
	test.expect(plan.run(warmupArgs) == CUSPARSE_STATUS_SUCCESS,
		"backend plan warmup on explicit stream succeeds");
	test.expect(cudaStreamSynchronize(stream) == cudaSuccess,
		"backend plan explicit-stream warmup completes");

	thrust::fill(inputs.denseC.begin(), inputs.denseC.end(), make_Complex(0.0, 0.0));
	thrust::device_vector<Complex> alternateDenseB = secondDenseB;
	thrust::device_vector<Complex> alternateDenseC(4, make_Complex(0.0, 0.0));
	auto firstArgs = makePlanArgs(context, inputs);
	firstArgs.stream = stream;
	auto secondArgs = makePlanArgs(context, inputs);
	secondArgs.stream = stream;
	secondArgs.denseInput = thrust::raw_pointer_cast(alternateDenseB.data());
	secondArgs.denseOutput = thrust::raw_pointer_cast(alternateDenseC.data());

	test.expect(plan.run(firstArgs) == CUSPARSE_STATUS_SUCCESS,
		"backend plan queues first same-stream dense pointer run");
	test.expect(plan.run(secondArgs) == CUSPARSE_STATUS_SUCCESS,
		"backend plan queues second same-stream dense pointer run without host sync");
	test.expect(cudaStreamSynchronize(stream) == cudaSuccess,
		"backend plan same-stream dense pointer runs complete");

	expectComplexVectorNear(test, thrust::host_vector<Complex>(inputs.denseC), firstExpected);
	expectComplexVectorNear(test, thrust::host_vector<Complex>(alternateDenseC), secondExpected);
	test.expect(plan.descriptorCreateCount() == 3,
		"same-stream dense pointer updates reuse descriptors");
	test.expect(plan.bufferSizeQueryCount() == 1,
		"same-stream dense pointer updates do not repeat buffer-size queries");

	cudaStreamDestroy(stream);
}

void testBackendPlanSteadyReuseReportsZeroSetupCounters(helix::test::Reporter& test)
{
	CusparseContext context(test);
	PlanInputs inputs = makePlanInputs();
	helix::cuda_backend::CudaSparseBackendPlan plan;

	test.expect(plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
		"backend plan warmup run succeeds before profiling steady reuse");
	test.expect(cudaDeviceSynchronize() == cudaSuccess, "backend plan warmup run completes");

	helix::library::BackendProfilingCounters snapshot;
	{
		helix::library::ScopedBackendProfiling profiling;
		thrust::fill(inputs.denseC.begin(), inputs.denseC.end(), make_Complex(0.0, 0.0));
		test.expect(plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
			"backend plan first steady reuse run succeeds");
		thrust::fill(inputs.denseC.begin(), inputs.denseC.end(), make_Complex(0.0, 0.0));
		test.expect(plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
			"backend plan second steady reuse run succeeds");
		test.expect(cudaDeviceSynchronize() == cudaSuccess, "backend plan steady reuse runs complete");
		snapshot = profiling.snapshot();
	}

	test.expect(snapshot.spmm.callCount.value_or(0) == 2,
		"steady reuse profiling counts only profiled SpMM calls");
	test.expect(snapshot.spmm.descriptorCreateCount.value_or(99) == 0,
		"steady reuse profiling records zero descriptor creation after warmup");
	test.expect(snapshot.spmm.workspaceAllocCount.value_or(99) == 0,
		"steady reuse profiling records zero workspace allocation after warmup");
	test.expect(snapshot.spmm.bufferSizeQueryCount.value_or(99) == 0,
		"steady reuse profiling records zero buffer-size queries after warmup");
}

void testBackendPlanRejectsShapeMismatch(helix::test::Reporter& test)
{
	CusparseContext context(test);
	PlanInputs inputs = makePlanInputs();
	helix::cuda_backend::CudaSparseBackendPlan plan;

	test.expect(
		plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
		"backend plan baseline shape succeeds before mismatch");

	const cusparseStatus_t mismatch = plan.run(makePlanArgs(context, inputs, 3, 2, 3));
	test.expect(mismatch != CUSPARSE_STATUS_SUCCESS, "backend plan rejects shape mismatch");
	test.expect(plan.spmmCallCount() == 1, "shape mismatch is not counted as a successful SpMM call");
}

void testBackendPlanDestroyRecreate(helix::test::Reporter& test)
{
	CusparseContext context(test);
	PlanInputs inputs = makePlanInputs();
	helix::cuda_backend::CudaSparseBackendPlan plan;

	test.expect(plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
		"backend plan run succeeds before destroy");
	plan.destroy();
	test.expect(!plan.initialized(), "backend plan destroy clears initialized state");
	test.expect(plan.run(makePlanArgs(context, inputs)) == CUSPARSE_STATUS_SUCCESS,
		"backend plan run succeeds after recreate");
	test.expect(plan.descriptorCreateCount() == 6, "backend plan recreate owns a fresh descriptor set");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testCsrmmNonTranspose(test);
	testCsrmm2TransposeB(test);
	testCsrmmReportsInvalidHandle(test);
	testBackendPlanReusesDescriptorsAndWorkspace(test);
	testBackendPlanUpdatesDensePointersWithoutRecreate(test);
	testBackendPlanQueuesDensePointerUpdatesOnSameStream(test);
	testBackendPlanSteadyReuseReportsZeroSetupCounters(test);
	testBackendPlanRejectsShapeMismatch(test);
	testBackendPlanDestroyRecreate(test);

	return test.finish("cuSPARSE wrapper CUDA tests");
}
