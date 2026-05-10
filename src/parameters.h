#pragma once

#include "cublas_v2.h"
#include "cuda_types.h"
#include <string>

class Param
{
public:
	static const double PI;
	static const int N;
	static const int N2;
	static const double Gamma;
	static double Betah;
	static const double Delta;
	static const double Omega0;
	static const double Dlong;
	static const double Dtrans;
	static double Step;
	static const int KMax;
	static const int JMax;
	static double Zeta;
	static const double JNaver;
	static const int OutputNum;
	static int IntegrationNum;
	static const int SnapShotNum;
	static const bool FromBoltzman;
	static std::string Filename;
	static const bool IsSquare;
};
extern const Complex iConst;

extern cublasHandle_t cublasHandle;
