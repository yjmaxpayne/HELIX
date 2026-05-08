#ifndef PSDDEF
#define PSDDEF

#include "thrust/host_vector.h"
#include "thrust/device_vector.h"
#include "cublas_v2.h"

enum PadeType
{
	NMinus1_N=0,
	N_N=1,
    NPlus1_N=2
};


extern bool getPsdPoleResidue(const int n,const bool isFermi,const PadeType type,
					thrust::host_vector<double>& poles,thrust::host_vector<double>& residues,double& R,double& T);

#endif
