#include "matrix_storage.h"
#include "cuda_types.h"

device_vector<Complex> dH;
device_vector<Complex> dV;
device_vector<Complex> dNu;
device_vector<Complex> dRho;
int hierarchySize;
device_vector<int> dHierarchies;
Complex KThetaCommutate,KThetaAntiCommutate;
host_vector<Complex> KPhi;
device_vector<Complex> dKPhi;
Complex KXi;
Complex KXiCounter;
device_vector<int> dHierarchyEdge;
device_vector<Complex> dBuffer;


device_vector<Complex> dHElements;
device_vector<Complex> dVElements;
device_vector<int> dHColumns;
device_vector<int> dVColumns;
device_vector<int> dHOffsets;
device_vector<int> dVOffsets;

template<typename T>
void releaseDeviceVector(device_vector<T>& values)
{
	device_vector<T>().swap(values);
}

void clearMatrixStorage()
{
	releaseDeviceVector(dH);
	releaseDeviceVector(dV);
	releaseDeviceVector(dNu);
	releaseDeviceVector(dRho);
	releaseDeviceVector(dHierarchies);
	releaseDeviceVector(dKPhi);
	releaseDeviceVector(dHierarchyEdge);
	releaseDeviceVector(dBuffer);
	releaseDeviceVector(dHElements);
	releaseDeviceVector(dVElements);
	releaseDeviceVector(dHColumns);
	releaseDeviceVector(dVColumns);
	releaseDeviceVector(dHOffsets);
	releaseDeviceVector(dVOffsets);
	KPhi.clear();
}
