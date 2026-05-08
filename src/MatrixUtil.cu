
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "thrust/host_vector.h"
#include "thrust/device_vector.h"
#include "thrust/functional.h"
#include <stdio.h>
#include <time.h>
#include <iostream>
#include "TypeDef.h"
#include "MatrixUtil.h"
#include "cublas_v2.h"

const int TILE_DIM=32;

__global__ void transpose(Complex* idata, int n, const int blockRows )
{
	__shared__ Complex block[ TILE_DIM*2 ][ TILE_DIM + 1 ];
	if(blockIdx.x==blockIdx.y)
	{
		int xIndex = blockIdx.x * TILE_DIM + threadIdx.x;
		int yIndex = blockIdx.y * TILE_DIM + threadIdx.y;
		int index = xIndex + (yIndex) * n;

		for( int i = 0; i < TILE_DIM; i += blockRows )
		{
			block[ threadIdx.y + i ][ threadIdx.x ] = idata[ index + i * n];
		}
		
		__syncthreads();
		
		for( int i = 0; i < TILE_DIM; i += blockRows )
		{
			idata[ index + i * n] = block[ threadIdx.x ][ threadIdx.y + i ];
		}
	}
	else if(blockIdx.x>blockIdx.y)
	{
		int xIndex = blockIdx.x * TILE_DIM + threadIdx.x;
		int yIndex = blockIdx.y * TILE_DIM + threadIdx.y;
		int index = xIndex + (yIndex) * n;
		int transIndex=yIndex + (xIndex) * n;
		for( int i = 0; i < TILE_DIM; i += blockRows )
		{
			block[ threadIdx.y + i ][ threadIdx.x ] = idata[ index + i * n];
			block[ threadIdx.y + i+TILE_DIM ][ threadIdx.x ] = idata[ transIndex + i];
		}
		
		__syncthreads();
		
		for( int i = 0; i < TILE_DIM; i += blockRows )
		{
			idata[transIndex + i] = block[ threadIdx.y+i ][ threadIdx.x ];
			idata[ index + i * n] = block[ threadIdx.y+i+TILE_DIM ][ threadIdx.x ];
		}
	}
}

__host__ void transpose(Complex* idata,const int n, const cudaStream_t &stream)
{
	static int blockRows=8;
	static dim3 block(n/TILE_DIM,n/TILE_DIM,1);
	static dim3 thread(TILE_DIM,blockRows,1);
	transpose<<<block,thread,0,stream>>>(idata,n,blockRows);
}
