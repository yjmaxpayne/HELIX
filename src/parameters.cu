#include "parameters.h"
#include <math.h>
#include "cuComplex.h"
#include "cublas_v2.h"

const double Param::PI=4.0*atan(1.0);
const Complex iConst=make_Complex(0,1.0);

//Parameters of Hamiltonian
//If you use original Hamiltonian and correlation operator, only N and N2 are necessary
const int Param::N=1<<10;
const int Param::N2=Param::N*Param::N;
const double Param::Delta=0;
const double Param::Omega0=1.0;
const double Param::Dlong=1.0;
const double Param::Dtrans=1.0;
const double Param::JNaver=0.6;
const bool Param::IsSquare=false;

//Parameters of time integration
double Param::Step=0.1;
int Param::IntegrationNum=4;

//Parameters of the bath
double Param::Betah=3;
const double Param::Gamma=1;
double Param::Zeta=0.01;

//Size of hierarchy
const int Param::KMax=2;
const int Param::JMax=3;

//If FromBoltzman is not true, this program tries to load snapshot
//If you want to begin with other situation (e.g. FID), you have to change initialize function in initialize.cu
const bool Param::FromBoltzman=true;
const int Param::OutputNum=1;
//If FromBoltzman is not true and SnapShotNum is less than zero, default snapshot(the filename is defined by Filename) is loaded
const int Param::SnapShotNum=-1;
std::string Param::Filename="";

cublasHandle_t cublasHandle;
