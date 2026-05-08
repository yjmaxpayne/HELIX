#ifndef EIGVALDEF
#define EIGVALDEF

#include "thrust/host_vector.h"
#include "thrust/device_vector.h"
#include "cublas_v2.h"

extern bool getEigval(int N,thrust::host_vector<double>& matrix);

#endif
