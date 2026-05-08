
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "Eigval.h"

#include <stdio.h>
#include <iostream>
#include <math.h>

const double alpha=1.0;
const double beta=0.0;

cublasHandle_t handle;
thrust::host_vector<double> mul(const thrust::host_vector<double>& A,const thrust::host_vector<double>& B,int n)
{
	thrust::host_vector<double> ret(n*n);
	thrust::device_vector<double> dA=A;
	thrust::device_vector<double> dB=B;
	thrust::device_vector<double> dC=ret;
	cublasDgemm(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,
		&alpha,raw_pointer_cast(dA.data()),n,raw_pointer_cast(dB.data()),n,&beta,raw_pointer_cast(dC.data()),n);
	cudaDeviceSynchronize();
	ret=dC;
	dA.clear();
	dB.clear();
	dC.clear();
	return ret;
}
void separate(int start,int end,thrust::host_vector<double>& matrix,int n)
{
	if(start>=end)
	{
		return;
	}
	int newN=end-start+1;
	thrust::host_vector<double> newMat(newN*newN);
	for(int y=start;y<=end;y++)
	{
		for(int x=start;x<=end;x++)
		{
			newMat[newN*(x-start)+y-start]=matrix[n*x+y];
		}
	}
	getEigval(newN,newMat);
	for(int y=start;y<=end;y++)
	{
		for(int x=start;x<=end;x++)
		{
			matrix[n*x+y]=newMat[newN*(x-start)+y-start];
		}
	}
}

bool getEigval(int N,thrust::host_vector<double>& matrix)
{
	cublasCreate(&handle);
	double error=1000;
	if(N==2)
	{
		double x00=matrix[0];
		double x10=matrix[1];
		double x01=matrix[2];
		double x11=matrix[3];
		double d=sqrt((x00-x11)*(x00-x11)+4.0*x10*x01);
		matrix[0]=0.5*(x00+x11+d);
		matrix[1]=0.0;
		matrix[2]=0.0;
		matrix[3]=0.5*(x00+x11-d);
		 return true;
	}
	do
	{
		for(int y=1;y<N;y++)
		{
			if(abs(matrix[y+(y-1)*N])<0.0000001){
				//std::cout<<y<<std::endl;
				separate(0,y-1,matrix,N);
				separate(y,N-1,matrix,N);
				return true;
			}
		}

		thrust::host_vector<double> matrixQI(N*N);
		for(int i=0;i<N;i++)
		{
			matrixQI[i+i*N]=1.0;
		}
		for(int i=N-1;i>0;i--)
		{
			thrust::host_vector<double> P(N*N);
			for(int j=0;j<N;j++)
			{
				P[j+j*N]=1.0;
			}
			double cos=matrix[i+i*N]/sqrt(matrix[i+i*N]*matrix[i+i*N]+matrix[i-1+i*N]*matrix[i-1+i*N]);
			double sin=matrix[i-1+i*N]/sqrt(matrix[i+i*N]*matrix[i+i*N]+matrix[i-1+i*N]*matrix[i-1+i*N]);
			P[i-1+(i-1)*N]=cos;
			P[i-1+i*N]=-sin;
			P[i+(i-1)*N]=sin;
			P[i+i*N]=cos;
			matrix=mul(P,matrix,N);
			P[i-1+i*N]=sin;
			P[i+(i-1)*N]=-sin;
			matrixQI=mul(matrixQI,P,N);
		}
		matrix=mul(matrix,matrixQI,N);
		error=0.0;
		for(int y=1;y<N;y++)
		{
			error+=abs(matrix[y+(y-1)*N]);
		}
		//std::cout<<error<<std::endl;
	}while(error>0.0000001);
	return true;
}
