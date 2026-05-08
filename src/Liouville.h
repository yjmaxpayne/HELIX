#ifndef INCLIOUVILLE
#define INCLIOUVILLE
#include "Matrixes.h"
#include "Parameters.h"
#include "cublas_v2.h"
#include "cusparse_v2.h"
#include "cuda_runtime.h"
#include <thrust/equal.h>
extern __global__ void initDeviceConstants();
extern void develop();
extern void clearLiouvilleStorage();
extern void getdRhoSparse(const device_vector<Complex>& rhoVec,device_vector<Complex>& drhoVec);
extern void getdRhowithBLAS(const device_vector<Complex>& rhoVec,device_vector<Complex>& drhoVec);
#endif
