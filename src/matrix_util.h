#pragma once

#include "cuda_types.h"

extern __host__ void transpose(Complex* idata,const int n, const cudaStream_t &stream);
