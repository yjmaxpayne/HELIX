#pragma once

#include "matrix_storage.h"
#include "parameters.h"
#include "cublas_v2.h"
#include "cusparse_v2.h"
#include "cuda_runtime.h"
#include <cstdlib>
#include <string>
#include <thrust/equal.h>

// M3.4 H-3.4.1: HELIX_DEBUG_SYNC_MODE=on adds defensive cudaDeviceSynchronize()
// alongside M3.2's event-based sync for first-error attribution during the
// segment-2-to-segment-5 migration. Off by default (event-based path is
// capture-friendly; debug mode intentionally disables capture).
inline bool helixDebugSyncEnabled()
{
	static const bool enabled = [] {
		const char* value = std::getenv("HELIX_DEBUG_SYNC_MODE");
		if(value == nullptr) return false;
		const std::string text(value);
		return text == "1" || text == "on" || text == "ON" || text == "true" || text == "TRUE";
	}();
	return enabled;
}

extern __global__ void initDeviceConstants();
extern void develop();
extern void clearLiouvilleStorage();
extern void addDiagonalHamiltonianCommutator(
	const Complex* diagonal,
	const Complex* rho,
	int n,
	Complex* result,
	cudaStream_t stream);
extern void getdRhoSparse(const device_vector<Complex>& rhoVec,device_vector<Complex>& drhoVec);
extern void getdRhowithBLAS(const device_vector<Complex>& rhoVec,device_vector<Complex>& drhoVec);
