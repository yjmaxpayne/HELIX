#ifndef MATINC
#define MATINC
#include "thrust/host_vector.h"
#include "thrust/device_vector.h"
#include "TypeDef.h"
using thrust::device_vector;
using thrust::host_vector;

extern device_vector<Complex> dH;
extern device_vector<Complex> dV;
extern device_vector<Complex> dNu;
extern device_vector<Complex> dRho;
extern int hierarchySize;
extern device_vector<int> dHierarchies;
extern Complex KThetaCommutate,KThetaAntiCommutate;
extern host_vector<Complex> KPhi;
extern device_vector<Complex> dKPhi;
extern Complex KXi;
extern Complex KXiCounter;
extern device_vector<int> dHierarchyEdge;
extern device_vector<Complex> dBuffer;

extern device_vector<Complex> dHElements;
extern device_vector<Complex> dVElements;
extern device_vector<int> dHColumns;
extern device_vector<int> dVColumns;
extern device_vector<int> dHOffsets;
extern device_vector<int> dVOffsets;

extern void clearMatrixStorage();
#endif
