#include "liouville.h"
#include "complex_operators.h"
#include "cuda_types.h"
#include "matrix_util.h"
using thrust::copy;
using thrust::device_vector;
using thrust::host_vector;
using thrust::raw_pointer_cast;

namespace {
template<typename T>
void releaseDeviceVector(device_vector<T>& values)
{
	device_vector<T>().swap(values);
}

device_vector<Complex>& developFStorage()
{
	static device_vector<Complex> values;
	return values;
}

device_vector<Complex>& developBStorage()
{
	static device_vector<Complex> values;
	return values;
}

device_vector<Complex>& sparseCoefficientStorage()
{
	static device_vector<Complex> values;
	return values;
}

device_vector<Complex>& sparseConstStorage()
{
	static device_vector<Complex> values;
	return values;
}

host_vector<cublasHandle_t>& sparseBlasHandles()
{
	static host_vector<cublasHandle_t> values;
	return values;
}

host_vector<cusparseHandle_t>& sparseCusparseHandles()
{
	static host_vector<cusparseHandle_t> values;
	return values;
}

host_vector<cudaStream_t>& sparseStreams()
{
	static host_vector<cudaStream_t> values;
	return values;
}

cusparseMatDescr_t& sparseMatDescr()
{
	static cusparseMatDescr_t value = nullptr;
	return value;
}

bool& sparseInitialized()
{
	static bool value = false;
	return value;
}
}

#ifdef DYNAMIC_DENSE
#define HEOM_LIOUVILLE_CALLABLE __host__ __device__
#else
#define HEOM_LIOUVILLE_CALLABLE __host__
#endif


__device__  Complex iCnt;
__device__  Complex minusiCnt;
__device__  Complex one;
__device__  Complex minusOne;
__device__  Complex zero;


__global__ void initDeviceConstants()
{
	iCnt=make_Complex(0.0,1.0);
	minusiCnt=make_Complex(0.0,-1.0);
	one=make_Complex(1.0,0.0);
	minusOne=make_Complex(-1.0,0.0);
	zero=make_Complex(0.0,0.0);
}

HEOM_LIOUVILLE_CALLABLE __inline__ void cublasError(const cublasStatus_t& status)
{
	if(status!=CUBLAS_STATUS_SUCCESS){
		printf("%d",(int)status);
	}
}

__device__ __host__ __inline__ void cusparseError(const cusparseStatus_t& status)
{
	if(status!=CUSPARSE_STATUS_SUCCESS){
		printf("%d",(int)status);
	}
}

HEOM_LIOUVILLE_CALLABLE __inline__ void addMatrix(cublasHandle_t handle,int n,const Complex* k,Complex* target,const Complex* add)
{
	cublasError(cublasAxpy(handle,n*n,k,add,1,target,1));
}


#ifdef DYNAMIC_DENSE
__device__ void Commutate(const cublasHandle_t &handle,const Complex* matrix1,const Complex* matrix2,const Complex* k,const int n,Complex* result)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix1,n,matrix2,n,&zero,result,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,&minusOne,result,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}

__device__ void antiCommutate(const cublasHandle_t &handle,const Complex* matrix1,const Complex* matrix2,const Complex* k,const int n,Complex* result)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,&zero,result,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix1,n,matrix2,n,&one,result,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}
__device__ void addCommutate(const cublasHandle_t &handle,Complex* target,const Complex* matrix1,const Complex* matrix2,const Complex* k,const Complex* minusK,const int n)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,minusK,matrix1,n,matrix2,n,&one,target,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,&one,target,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}
__device__ void addAntiCommutate(const cublasHandle_t &handle,Complex* target,const Complex* matrix1,const Complex* matrix2,const Complex* k,const int n)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,&one,target,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix1,n,matrix2,n,&one,target,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}
#endif

Complex* pOne,*pZero,*pMinusOne,*pMinusiCnt,*piCnt;
__host__ __inline__ void CommutateHost(const cublasHandle_t &handle,const Complex* matrix1,const Complex* matrix2,const Complex* k,const int n,Complex* result)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix1,n,matrix2,n,pZero,result,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,pMinusOne,result,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}

__host__ __inline__ void antiCommutateHost(const cublasHandle_t &handle,const Complex* matrix1,const Complex* matrix2,const Complex* k,const int n,Complex* result)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,pZero,result,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix1,n,matrix2,n,pOne,result,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}
__host__ __inline__ void addCommutateHost(const cublasHandle_t &handle,Complex* target,const Complex* matrix1,const Complex* matrix2,const Complex* k,const Complex* minusK,const int n)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,minusK,matrix1,n,matrix2,n,pOne,target,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,pOne,target,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}
__host__ __inline__ void addAntiCommutateHost(const cublasHandle_t &handle,Complex* target,const Complex* matrix1,const Complex* matrix2,const Complex* k,const int n)
{
	cublasStatus_t st1=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix2,n,matrix1,n,pOne,target,n);
	cublasStatus_t st2=cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,k,matrix1,n,matrix2,n,pOne,target,n);
	if(st1!=0||st2!=0){printf("%s","error\n");}
}
__host__ __inline__ void CommutateSparse(const cusparseHandle_t &handle,const cudaStream_t & stream,const cusparseMatDescr_t MatDescr, const Complex* elements,const int* columns,const int* offsets,const int nnz,const Complex* matrixDence,const Complex* k,const int n,Complex* result)
{
	cusparseError(cusparseCsrmm(handle,CUSPARSE_OPERATION_NON_TRANSPOSE,n,n,n,nnz,k,MatDescr,
		elements,offsets,columns,
		matrixDence,n,pZero,result,n));
	transpose(result,n,stream);

	cusparseError(cusparseCsrmm2(handle,CUSPARSE_OPERATION_NON_TRANSPOSE,CUSPARSE_OPERATION_TRANSPOSE,n,n,n,nnz,k,MatDescr,
		elements,offsets,columns,
		matrixDence,n,pMinusOne,result,n));

	transpose(result,n,stream);
}
__host__ __inline__ void addCommutateSparse(const cusparseHandle_t &handle,const cudaStream_t & stream,const cusparseMatDescr_t MatDescr, const Complex* elements,const int* columns,const int* offsets,const int nnz,const Complex* matrixDence,const Complex* k,const Complex* minusK,const int n,Complex* result)
{
	cusparseError(cusparseCsrmm(handle,CUSPARSE_OPERATION_NON_TRANSPOSE,n,n,n,nnz,minusK,MatDescr,
		elements,offsets,columns,
		matrixDence,n,pOne,result,n));

	transpose(result,n,stream);

	cusparseError(cusparseCsrmm2(handle,CUSPARSE_OPERATION_NON_TRANSPOSE,CUSPARSE_OPERATION_TRANSPOSE,n,n,n,nnz,k,MatDescr,
		elements,offsets,columns,
		matrixDence,n,pOne,result,n));

	transpose(result,n,stream);
}
__host__ __inline__ void addAntiCommutateSparse(const cusparseHandle_t &handle,const cudaStream_t & stream,const cusparseMatDescr_t MatDescr, const Complex* elements,const int* columns,const int* offsets,const int nnz,const Complex* matrixDence,const Complex* k,const int n,Complex* result)
{
	cusparseError(cusparseCsrmm(handle,CUSPARSE_OPERATION_NON_TRANSPOSE,n,n,n,nnz,k,MatDescr,
		elements,offsets,columns,
		matrixDence,n,pOne,result,n));

	transpose(result,n,stream);

	cusparseError(cusparseCsrmm2(handle,CUSPARSE_OPERATION_NON_TRANSPOSE,CUSPARSE_OPERATION_TRANSPOSE,n,n,n,nnz,k,MatDescr,
		elements,offsets,columns,
		matrixDence,n,pOne,result,n));

	transpose(result,n,stream);
}

#ifdef DYNAMIC_DENSE
__global__ void getdRhoKernelPrepare(
	const Complex* __restrict__ Rho,
	Complex* __restrict__ dRho,
	const Complex* __restrict__ h,
	const Complex* __restrict__ v,
	Complex* buffer,
	const int n)
{
	cublasHandle_t handle;
	cublasError(cublasCreate(&handle));
	int index=blockIdx.x;

	//L
#ifdef H_DIAGONAL //if H is diagonal
	cublasDgmm(handle,CUBLAS_SIDE_LEFT,n,n,Rho+index*n*n,n,h,n+1,dRho+index*n*n,n);
	cublasGemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,&minusiCnt,Rho+index*n*n,n,h,n,&iCnt,dRho+index*n*n,n);
#else
	Commutate(handle,h,Rho+index*n*n,&minusiCnt,n,dRho+index*n*n);
#endif

	//Calculate commutator of V and finish kernel to synchronize
	Commutate(handle,v,Rho+index*n*n,&one,n,buffer+index*n*n);
	cublasDestroy(handle);
}
__global__ void getdRhoKernel(
	const int* numbers,
	const int* edges,
	const Complex* __restrict__ Rho,
	Complex* __restrict__ dRho,
	const Complex* __restrict__ h,
	const Complex* __restrict__ v,
	const Complex* __restrict__ nu,
	const Complex kThetaCommutate,
	const Complex kThetaAntiCommutate,
	const Complex kXi,
	const Complex kXiCounter,
	const Complex* phi,
	Complex* buffer,
	const int kMax,
	const int jMax,
	const int n,
	const int size,
	Complex* tmp)
{
	cublasHandle_t handle;
	cublasError(cublasCreate(&handle));
	int index=blockIdx.x;
	int indexmMinus1=edges[index*(kMax*2+2)+kMax+1];
	//phi
	for(int i=0;i<kMax+1;i++)
	{
		int indexkPlus1=edges[index*(kMax*2+2)+i];
		addMatrix(handle,n,&minusiCnt,dRho+index*n*n,buffer+indexkPlus1*n*n);
	}

	//psi
	for(int i=1;i<kMax+1;i++)
	{
		int indexkMinus1=edges[index*(kMax*2+2)+kMax+1+i];
		double jNuD=-nu[i].x*numbers[index*(kMax+1)+i];
		tmp[index]=make_Complex(phi[i-1].x*jNuD,phi[i-1].y*jNuD);
		addMatrix(handle,n,&tmp[index],dRho+index*n*n,buffer+indexkMinus1*n*n);
	}

	//theta
	double ngamma=-nu[0].x*numbers[index*(kMax+1)];
	tmp[index]=make_Complex(ngamma*kThetaCommutate.x,ngamma*kThetaCommutate.y);
	addMatrix(handle,n,&tmp[index],dRho+index*n*n,buffer+indexmMinus1*n*n);

	//theta2
	tmp[index]=make_Complex(ngamma*kThetaAntiCommutate.x,ngamma*kThetaAntiCommutate.y);
	addAntiCommutate(handle,dRho+index*n*n,v,Rho+indexmMinus1*n*n,&tmp[index],n);

	//Sigma
	double sum=0.0;
	for(int i=0;i<kMax+1;i++)
	{
		sum+=nu[i].x*numbers[index*(kMax+1)+i];
	}
	tmp[index]=make_Complex(-sum,0.0);
	addMatrix(handle,n,&tmp[index],dRho+index*n*n,Rho+index*n*n);

	//Xi
	tmp[index]=make_Complex(-kXi.x,-kXi.y);
	tmp[index+size]=make_Complex(kXi.x,kXi.y);
	addCommutate(handle,dRho+index*n*n,v,buffer+index*n*n,&tmp[index],&tmp[index+size],n);

#ifdef USE_COUNTER
	tmp[index]=make_Complex(-kXiCounter.x,-kXiCounter.y);
	addAntiCommutate(handle,dRho+index*n*n,v,buffer+index*n*n,&tmp[index],n);
#endif

	cublasDestroy(handle);
}
#endif

void develop()
{
	int rhoSize=hierarchySize*Param::N2;


	double t=Param::Step;
	int m=Param::IntegrationNum;
	device_vector<Complex>& F=developFStorage();
	device_vector<Complex>& B=developBStorage();
	if(F.size()!=rhoSize){ F.resize(rhoSize); }
	if(B.size()!=rhoSize){ B.resize(rhoSize); }
	F=dRho;
	static Complex one=make_Complex(1.0,0.0);
	static Complex minusOne=make_Complex(-1.0,0.0);
	static Complex zero=make_Complex(0.0,0.0);
	for(int j=1;j<=m;j++)
	{
		Complex tj=make_Complex(t/j,0.0);
#ifdef DYNAMIC_DENSE
		getdRhowithBLAS(dRho,B);
#else
		getdRhoSparse(dRho,B);
#endif
		cublasError(cublasScal(cublasHandle,rhoSize,&tj,raw_pointer_cast(B.data()),1));

		cublasError(cublasAxpy(cublasHandle,rhoSize,&one,raw_pointer_cast(B.data()),1,raw_pointer_cast(F.data()),1));

		cudaDeviceSynchronize();
		copy(B.begin(),B.end(),dRho.begin());
	}
	copy(F.begin(),F.end(),dRho.begin());

	//RK4
	/*Complex* rho=raw_pointer_cast(dRho.data());
	static device_vector<Complex> dRhoTmp=device_vector<Complex>(rhoSize);
	static device_vector<Complex> RhoN=device_vector<Complex>(rhoSize+Param::N2);
	static host_vector<Complex> Rho1=host_vector<Complex>(rhoSize);
	static host_vector<Complex> Rho2=host_vector<Complex>(rhoSize);
	static host_vector<Complex> Rho3=host_vector<Complex>(rhoSize);

	static Complex* pdRhoTmp=raw_pointer_cast(dRhoTmp.data());
	static Complex* pRhoN=raw_pointer_cast(RhoN.data());
	const Complex h2Complex=make_Complex(0.5*Param::Step,0.0);
	const Complex hComplex=make_Complex(Param::Step,0.0);
	const Complex h3Complex=make_Complex(Param::Step/3,0.0);
	const Complex h6Complex=make_Complex(Param::Step/6,0.0);
	getdRho(dRho,dRhoTmp);
	copy(dRho.begin(),dRho.end(),RhoN.begin());
	cudaDeviceSynchronize();
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&h2Complex,pdRhoTmp,1,pRhoN,1));

	cudaDeviceSynchronize();
	Rho1=dRhoTmp;

	getdRho(RhoN,dRhoTmp);
	copy(dRho.begin(),dRho.end(),RhoN.begin());
	cudaDeviceSynchronize();
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&h2Complex,pdRhoTmp,1,pRhoN,1));
	Rho2=dRhoTmp;


	getdRho(RhoN,dRhoTmp);
	copy(dRho.begin(),dRho.end(),RhoN.begin());
	cudaDeviceSynchronize();
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&hComplex,pdRhoTmp,1,pRhoN,1));
	cudaDeviceSynchronize();
	Rho3=dRhoTmp;

	getdRho(RhoN,dRhoTmp);
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&h6Complex,pdRhoTmp,1,rho,1));

	dRhoTmp=Rho1;
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&h6Complex,pdRhoTmp,1,rho,1));

	dRhoTmp=Rho2;
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&h3Complex,pdRhoTmp,1,rho,1));

	dRhoTmp=Rho3;
	cublasError(cublasZaxpy(cublasHandle,rhoSize,&h3Complex,pdRhoTmp,1,rho,1));


	cudaThreadSynchronize();
	cublasDestroy(cublasHandle);*/
}

#ifdef DYNAMIC_DENSE
void getdRhowithBLAS(const device_vector<Complex>& rhoVec,device_vector<Complex>& drhoVec)
{
	static const Complex* pRho=raw_pointer_cast(rhoVec.data());
	static Complex* pdRho=raw_pointer_cast(drhoVec.data());
	static const int* hie=raw_pointer_cast(dHierarchies.data());
	static int* pEdge=raw_pointer_cast(dHierarchyEdge.data());
	Complex* pdNu=raw_pointer_cast(dNu.data());
	static int grid=hierarchySize;
	static device_vector<Complex> tmp(grid*2);

	getdRhoKernelPrepare<<<grid,1>>>(
		pRho,
		pdRho,
		raw_pointer_cast(dH.data()),
		raw_pointer_cast(dV.data()),
		raw_pointer_cast(dBuffer.data()),
		Param::N);
	cudaDeviceSynchronize();
	getdRhoKernel<<<grid,1>>>(
		hie,
		pEdge,
		pRho,
		pdRho,
		raw_pointer_cast(dH.data()),
		raw_pointer_cast(dV.data()),
		pdNu,
		KThetaCommutate,
		KThetaAntiCommutate,
		KXi,KXiCounter,
		raw_pointer_cast(dKPhi.data()),
		raw_pointer_cast(dBuffer.data()),
		Param::KMax,Param::JMax,Param::N,hierarchySize,
		raw_pointer_cast(tmp.data()));
	cudaError_t er= cudaGetLastError();
	printf("%s",(er==0)?"":cudaGetErrorString(er));
	cudaDeviceSynchronize();
}
#endif

bool initSparse(host_vector<cudaStream_t>& streams,host_vector<cublasHandle_t>& blasHandles,host_vector<cusparseHandle_t>& sparseHandles,device_vector<Complex>& coefficients,cusparseMatDescr_t& matDescr)
{
	host_vector<int> numbers=dHierarchies;
	int kMax=Param::KMax;
	host_vector<Complex> nu=dNu;

	host_vector<Complex> consts(5);
	consts[0]=make_Complex(0.0,0.0);
	consts[1]=make_Complex(1.0,0.0);
	consts[2]=make_Complex(-1.0,0.0);
	consts[3]=make_Complex(0.0,1.0);
	consts[4]=make_Complex(0.0,-1.0);
	device_vector<Complex>& dConsts=sparseConstStorage();
	dConsts=consts;
	Complex* pdConsts=raw_pointer_cast(dConsts.data());
	pZero=pdConsts;
	pOne=pdConsts+1;
	pMinusOne=pdConsts+2;
	piCnt=pdConsts+3;
	pMinusiCnt=pdConsts+4;

	for(int i=0;i<hierarchySize;i++)
	{
		cudaStreamCreate(&streams[i]);
		cublasCreate(&blasHandles[i]);
		cublasSetStream(blasHandles[i],streams[i]);
		cublasSetPointerMode(blasHandles[i],CUBLAS_POINTER_MODE_DEVICE);
		cusparseCreate(&sparseHandles[i]);
		cusparseSetStream(sparseHandles[i],streams[i]);
		cusparseSetPointerMode(sparseHandles[i],CUSPARSE_POINTER_MODE_DEVICE);
	}

    cusparseCreateMatDescr(&matDescr);
    cusparseSetMatType(matDescr, CUSPARSE_MATRIX_TYPE_GENERAL);
    cusparseSetMatIndexBase(matDescr, CUSPARSE_INDEX_BASE_ZERO);

	host_vector<Complex> tmp(hierarchySize*(7+Param::KMax));
	for(int index=0;index<hierarchySize;index++)
	{
		for(int i=1;i<kMax+1;i++)
		{
			double jNuD=-nu[i].x*numbers[index*(kMax+1)+i];
			tmp[index+hierarchySize*(i-1)]=make_Complex(KPhi[i-1].x*jNuD,KPhi[i-1].y*jNuD);
		}
		double ngamma=-nu[0].x*numbers[index*(kMax+1)];
		tmp[index+hierarchySize*(kMax+1)]=make_Complex(ngamma*KThetaCommutate.x,ngamma*KThetaCommutate.y);
		tmp[index+hierarchySize*(kMax+2)]=make_Complex(ngamma*KThetaAntiCommutate.x,ngamma*KThetaAntiCommutate.y);
		double sum=0.0;
		for(int i=0;i<kMax+1;i++)
		{
			sum+=nu[i].x*numbers[index*(kMax+1)+i];
		}
		tmp[index+hierarchySize*(kMax+3)]=make_Complex(-sum,0.0);
		tmp[index+hierarchySize*(kMax+4)]=make_Complex(-KXi.x,-KXi.y);
		tmp[index+hierarchySize*(kMax+5)]=make_Complex(KXi.x,KXi.y);
		tmp[index+hierarchySize*(kMax+6)]=make_Complex(-KXiCounter.x,-KXiCounter.y);
	}

	thrust::copy(tmp.begin(),tmp.end(),coefficients.begin());
	return true;
}

void getdRhoSparse(const device_vector<Complex>& rhoVec,device_vector<Complex>& drhoVec)
{
	host_vector<cublasHandle_t>& blasHandles=sparseBlasHandles();
	host_vector<cusparseHandle_t>& sparseHandles=sparseCusparseHandles();
	host_vector<cudaStream_t>& streams=sparseStreams();
	device_vector<Complex>& coefficients=sparseCoefficientStorage();
	cusparseMatDescr_t& MatDescr=sparseMatDescr();
	if(!sparseInitialized())
	{
		blasHandles.resize(hierarchySize, nullptr);
		sparseHandles.resize(hierarchySize, nullptr);
		streams.resize(hierarchySize, nullptr);
		coefficients.resize(hierarchySize*(7+Param::KMax));
		sparseInitialized()=initSparse(streams,blasHandles,sparseHandles,coefficients,MatDescr);
	}
	Complex* pCoefficients=raw_pointer_cast(coefficients.data());
	const Complex* pRho=raw_pointer_cast(rhoVec.data());
	Complex* pdRho=raw_pointer_cast(drhoVec.data());
	int n =Param::N;
	Complex* buffer=raw_pointer_cast(dBuffer.data());
	host_vector<int> edges=dHierarchyEdge;
	int kMax=Param::KMax;
	int vSize=dVElements.size();
	for(int i=0;i<hierarchySize;i++)
	{
		int index=i;
		//L
#ifdef H_DIAGONAL //if H is diagonal
		cublasError(cublasDgmm(blasHandles[i],CUBLAS_SIDE_LEFT,n,n,pRho+index*n*n,n,raw_pointer_cast(dHElements.data()),1,pdRho+index*n*n,n));
		transpose(pdRho+index*n*n,n,streams[i]);
		cusparseError(cusparseCsrmm2(sparseHandles[i],CUSPARSE_OPERATION_NON_TRANSPOSE,CUSPARSE_OPERATION_TRANSPOSE,n,n,n,n,pMinusiCnt,MatDescr,
			raw_pointer_cast(dHElements.data()),raw_pointer_cast(dHOffsets.data()),raw_pointer_cast(dHColumns.data()),
			pRho+index*n*n,n,piCnt,pdRho+index*n*n,n));
		transpose(pdRho+index*n*n,n,streams[i]);
#else
		CommutateSparse(sparseHandles[i],streams[i],MatDescr,
			raw_pointer_cast(dHElements.data()),raw_pointer_cast(dHColumns.data()),raw_pointer_cast(dHOffsets.data()),
			dHElements.size(),pRho+index*n*n,pMinusiCnt,n,pdRho+index*n*n);
#endif
		CommutateSparse(sparseHandles[i],streams[i],MatDescr,
			raw_pointer_cast(dVElements.data()),raw_pointer_cast(dVColumns.data()),raw_pointer_cast(dVOffsets.data()),
			vSize,pRho+index*n*n,pOne,n,buffer+index*n*n);
	}
	cudaDeviceSynchronize();
	for(int i=0;i<hierarchySize;i++)
	{
		int index=i;
		int indexmMinus1=edges[index*(kMax*2+2)+kMax+1];
		//phi
		for(int k=0;k<kMax+1;k++)
		{
			int indexkPlus1=edges[index*(kMax*2+2)+k];
			addMatrix(blasHandles[index],n,pMinusiCnt,pdRho+index*n*n,buffer+indexkPlus1*n*n);
		}

		//psi
		for(int k=1;k<kMax+1;k++)
		{
			int indexkMinus1=edges[index*(kMax*2+2)+kMax+1+k];
			addMatrix(blasHandles[index],n,&pCoefficients[index+hierarchySize*(k-1)],pdRho+index*n*n,buffer+indexkMinus1*n*n);
		}

		//theta
		addMatrix(blasHandles[index],n,&pCoefficients[index+hierarchySize*(kMax+1)],pdRho+index*n*n,buffer+indexmMinus1*n*n);

		//theta2
		//addAntiCommutateHost(blasHandles[index],pdRho+index*n*n,v,pRho+indexmMinus1*n*n,&pCoefficients[index+hierarchySize*(kMax+2)],n);
		addAntiCommutateSparse(sparseHandles[i],streams[i],MatDescr,
			raw_pointer_cast(dVElements.data()),raw_pointer_cast(dVColumns.data()),raw_pointer_cast(dVOffsets.data()),
			vSize,pRho+indexmMinus1*n*n,&pCoefficients[index+hierarchySize*(kMax+2)],n,pdRho+index*n*n);

		//Sigma
		addMatrix(blasHandles[index],n,&pCoefficients[index+hierarchySize*(kMax+3)],pdRho+index*n*n,pRho+index*n*n);

		//Xi
		//addCommutateHost(blasHandles[index],pdRho+index*n*n,v,buffer+index*n*n,&pCoefficients[index+hierarchySize*(kMax+4)],&pCoefficients[index+hierarchySize*(kMax+5)],n);
		addCommutateSparse(sparseHandles[i],streams[i],MatDescr,
			raw_pointer_cast(dVElements.data()),raw_pointer_cast(dVColumns.data()),raw_pointer_cast(dVOffsets.data()),
			vSize,buffer+index*n*n,&pCoefficients[index+hierarchySize*(kMax+4)],&pCoefficients[index+hierarchySize*(kMax+5)],n,pdRho+index*n*n);

	#ifdef USE_COUNTER
		//addAntiCommutateHost(blasHandles[index],pdRho+index*n*n,v,buffer+index*n*n,&pCoefficients[index+hierarchySize*(kMax+6)],n);
		addAntiCommutateSparse(sparseHandles[i],streams[i],MatDescr,
			raw_pointer_cast(dVElements.data()),raw_pointer_cast(dVColumns.data()),raw_pointer_cast(dVOffsets.data()),
			vSize,buffer+index*n*n,&pCoefficients[index+hierarchySize*(kMax+6)],n,pdRho+index*n*n);
	#endif

	}
	cudaDeviceSynchronize();
}

void clearLiouvilleStorage()
{
	cudaDeviceSynchronize();
	host_vector<cudaStream_t>& streams=sparseStreams();
	host_vector<cublasHandle_t>& blasHandles=sparseBlasHandles();
	host_vector<cusparseHandle_t>& cusparseHandles=sparseCusparseHandles();
	for(size_t i=0;i<streams.size();i++)
	{
		if(streams[i]!=nullptr)
		{
			cudaStreamSynchronize(streams[i]);
		}
		if(blasHandles.size()>i && blasHandles[i]!=nullptr)
		{
			cublasDestroy(blasHandles[i]);
			blasHandles[i]=nullptr;
		}
		if(cusparseHandles.size()>i && cusparseHandles[i]!=nullptr)
		{
			cusparseDestroy(cusparseHandles[i]);
			cusparseHandles[i]=nullptr;
		}
		if(streams[i]!=nullptr)
		{
			cudaStreamDestroy(streams[i]);
			streams[i]=nullptr;
		}
	}
	if(sparseMatDescr()!=nullptr)
	{
		cusparseDestroyMatDescr(sparseMatDescr());
		sparseMatDescr()=nullptr;
	}
	releaseDeviceVector(developFStorage());
	releaseDeviceVector(developBStorage());
	releaseDeviceVector(sparseCoefficientStorage());
	releaseDeviceVector(sparseConstStorage());
	blasHandles.clear();
	cusparseHandles.clear();
	streams.clear();
	sparseInitialized()=false;
}
