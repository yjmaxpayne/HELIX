#pragma once

#include "cuda_types.h"

// In-place square transpose for TILE_DIM-multiple matrices; unsupported shapes are not launched.
extern __host__ void transpose(Complex* idata,const int n, const cudaStream_t &stream);
