#ifndef DEFMATU
#define DEFMATU
#include "TypeDef.h"

extern __host__ void transpose(Complex* idata,const int n, const cudaStream_t &stream);

#endif
