#include "initialize.h"
#include "initialize_detail.h"
#include "liouville.h"
#include "cuda_types.h"
#include <cstdlib>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>

thrust::host_vector<double> poles, residues;

namespace {

struct DenseOperators
{
	host_vector<Complex> V;
	host_vector<Complex> H;
};

#ifndef DYNAMIC_DENSE
struct SparseOperators
{
	host_vector<Complex> VElements;
	host_vector<Complex> HElements;
	host_vector<int> VColumns;
	host_vector<int> HColumns;
	host_vector<int> VOffsets;
	host_vector<int> HOffsets;
};
#endif

std::string buildDefaultSnapshotFilename()
{
	std::stringstream rhos;
	rhos << "rho1_n9_j";
	rhos << Param::JMax;
	rhos << "_";
	rhos << Param::JMax;
	rhos << "_";
	rhos << Param::KMax;
	rhos << "_Jn";
	rhos << static_cast<int>(Param::JNaver * 10);
	if(Param::IsSquare)
	{
		rhos << "_sq";
	}
#ifdef SINGLE
	rhos << "_f";
#endif
	rhos << ".dat";
	return rhos.str();
}

void assignDenseOffDiagonalTerms(int row, DenseOperators& operators)
{
	for(int column = 0; column < Param::N; column++)
	{
		if(initialize_detail::isDenseFlipMask(row ^ column))
		{
			operators.V[row * Param::N + column] = make_Complex(Param::Dtrans, 0.0);
			operators.H[row * Param::N + column] = make_Complex(Param::Delta, 0.0);
		}
	}
}

DenseOperators buildDenseOperators(const host_vector<double>& couplings, int spinCount)
{
	DenseOperators operators = {
		host_vector<Complex>(Param::N2, make_Complex(0.0, 0.0)),
		host_vector<Complex>(Param::N2, make_Complex(0.0, 0.0))
	};

	for(int state = 0; state < Param::N; state++)
	{
		host_vector<double> projections = initialize_detail::spinProjections(state, spinCount, Param::Omega0);
		double projectionSum = initialize_detail::sumProjections(projections);
		double hDiagonal = initialize_detail::hamiltonianDiagonal(couplings, projections, spinCount);

		operators.V[state * Param::N + state] = make_Complex(Param::Dlong * projectionSum, 0.0);
		operators.H[state * Param::N + state] = make_Complex(hDiagonal, 0.0);
		assignDenseOffDiagonalTerms(state, operators);
	}

	return operators;
}

void copyDenseOperatorsToDevice(const DenseOperators& operators)
{
	dV = operators.V;
	dH = operators.H;
}

#ifndef DYNAMIC_DENSE
void assignSparseRow(
	int row,
	double vDiagonal,
	double hDiagonal,
	int& vNonZeroCount,
	SparseOperators& operators)
{
	for(int column = 0; column < Param::N; column++)
	{
		if(row == column)
		{
			operators.HElements[row] = make_Complex(hDiagonal, 0.0);
			operators.HColumns[row] = row;
			operators.VElements[vNonZeroCount] = make_Complex(vDiagonal, 0.0);
			operators.VColumns[vNonZeroCount] = row;
			vNonZeroCount++;
		}

		if(initialize_detail::isSparseFlipMask(row ^ column))
		{
			operators.VElements[vNonZeroCount] = make_Complex(Param::Dtrans, 0.0);
			operators.VColumns[vNonZeroCount] = column;
			vNonZeroCount++;
		}
	}

	operators.VOffsets[row + 1] = vNonZeroCount;
	operators.HOffsets[row + 1] = row + 1;
}

SparseOperators buildSparseOperators(const host_vector<double>& couplings, int spinCount)
{
	SparseOperators operators = {
		host_vector<Complex>(Param::N * (spinCount + 1), make_Complex(0.0, 0.0)),
		host_vector<Complex>(Param::N, make_Complex(0.0, 0.0)),
		host_vector<int>(Param::N * (spinCount + 1), 0),
		host_vector<int>(Param::N, 0),
		host_vector<int>(Param::N + 1, 0),
		host_vector<int>(Param::N + 1, 0)
	};

	int vNonZeroCount = 0;
	for(int state = 0; state < Param::N; state++)
	{
		host_vector<double> projections = initialize_detail::spinProjections(state, spinCount, Param::Omega0);
		double projectionSum = initialize_detail::sumProjections(projections);
		double vDiagonal = Param::Dlong * projectionSum;
		double hDiagonal = initialize_detail::hamiltonianDiagonal(couplings, projections, spinCount);
		assignSparseRow(state, vDiagonal, hDiagonal, vNonZeroCount, operators);
	}

	return operators;
}

void copySparseOperatorsToDevice(const SparseOperators& operators)
{
	dVElements = operators.VElements;
	dVColumns = operators.VColumns;
	dVOffsets = operators.VOffsets;
	dHElements = operators.HElements;
	dHColumns = operators.HColumns;
	dHOffsets = operators.HOffsets;
}
#endif

host_vector<double> buildBathFrequencies()
{
	host_vector<double> Nu(Param::KMax + 1);
	Nu[0] = Param::Gamma;
	for(int i = 1; i <= Param::KMax; i++)
	{
		Nu[i] = poles[i - 1] / Param::Betah;
	}
	return Nu;
}

void copyBathFrequenciesToDevice(const host_vector<double>& Nu)
{
	dNu = device_vector<Complex>(Param::KMax + 1);
	for(int i = 0; i <= Param::KMax; i++)
	{
		dNu[i] = make_Complex(Nu[i], 0.0);
	}
}

double calculateSigma(const host_vector<double>& Nu, double betaGammaHalf, double betaOmega)
{
	double sigma = 1.0 - betaGammaHalf / tan(betaGammaHalf);
	for(int i = 1; i <= Param::KMax; i++)
	{
		sigma = sigma - 2.0 * residues[i - 1] * Param::Gamma * Param::Gamma
			/ ((Nu[i] * Nu[i]) - Param::Gamma * Param::Gamma);
	}
	return sigma * (Param::Zeta / betaOmega);
}

host_vector<Complex> buildKPhi(const host_vector<double>& Nu, double betaOmega)
{
	host_vector<Complex> phi(Param::KMax);
	for(int i = 1; i <= Param::KMax; i++)
	{
		phi[i - 1] = make_Complex(
			0.0,
			(Param::Zeta / betaOmega) * 2.0 * residues[i - 1] * Param::Gamma * Param::Gamma
				/ ((Nu[i] * Nu[i]) - Param::Gamma * Param::Gamma));
	}
	return phi;
}

void initializeBathCoefficients(const host_vector<double>& Nu)
{
	double betaGammaHalf = 0.5 * Param::Betah * Param::Gamma;
	double betaOmega = Param::Betah * Param::Omega0;

	KXi = make_Complex(calculateSigma(Nu, betaGammaHalf, betaOmega), 0.0);
	KXiCounter = make_Complex(0.0, Param::Zeta * betaGammaHalf / betaOmega);
	KPhi = buildKPhi(Nu, betaOmega);
	dKPhi = KPhi;
	KThetaCommutate = make_Complex(
		0.0,
		Param::Betah * Param::Gamma * 0.5 / tan(Param::Betah * Param::Gamma * 0.5)
			* Param::Zeta / betaOmega);
	KThetaAntiCommutate = make_Complex(Param::Betah * Param::Gamma * 0.5 * Param::Zeta / betaOmega, 0.0);
}

void initializePsdData()
{
	double R;
	double T;
	getPsdPoleResidue(Param::KMax, false, NMinus1_N, poles, residues, R, T);
}

void initializeCublas()
{
	cublasStatus_t status = cublasCreate(&cublasHandle);
	if(status != CUBLAS_STATUS_SUCCESS)
	{
		fprintf(stderr, "!!!! CUBLAS initialization error\n");
		exit(status);
	}
}

void initializeHierarchyStorage()
{
	const int modeCount = Param::KMax + 1;
	hierarchySize = getHierarchySize(modeCount, Param::JMax);

	host_vector< host_vector<int> > hierarchy(hierarchySize, host_vector<int>(modeCount));
	int rowCount = 0;
	createHierarchy(0, rowCount, host_vector<int>(0), hierarchy, Param::JMax);
	dHierarchies = initialize_detail::flattenRows(hierarchy, modeCount);

	host_vector< host_vector<int> > edges(hierarchySize, host_vector<int>(modeCount * 2));
	getHierarchyEdge(hierarchy, edges);
	dHierarchyEdge = initialize_detail::flattenRows(edges, modeCount * 2);
}

std::string inputRhoFilename()
{
	if(Param::SnapShotNum < 0)
	{
		return Param::Filename;
	}

	std::stringstream snapshot;
	snapshot << "snapshot_rho";
	snapshot << Param::SnapShotNum;
	snapshot << ".dat";
	return snapshot.str();
}

void loadRhoFromSnapshot(host_vector<Complex>& rho)
{
	std::string name = inputRhoFilename();
	std::ifstream fin(name, std::ios::in | std::ios::binary);
	if(!fin)
	{
		std::cout << "File " << name << " cannnot be opened";
		throw;
	}

	for(int i = 0; i < hierarchySize * Param::N2; i++)
	{
		real x;
		real y;
		fin.read(reinterpret_cast<char*>(&x), sizeof(real));
		fin.read(reinterpret_cast<char*>(&y), sizeof(real));
		rho[i] = make_Complex(x, y);
	}
	fin.close();
}

host_vector<Complex> buildInitialRho()
{
	host_vector<Complex> rho(Param::N2 * (hierarchySize + 1), make_Complex(0.0, 0.0));

	if(Param::FromBoltzman)
	{
		rho[Param::N2 - 1] = make_Complex(1.0, 0.0);
	}
	else
	{
		loadRhoFromSnapshot(rho);
	}

	return rho;
}

void initializeRhoAndBuffer()
{
	dRho = buildInitialRho();
	dBuffer = host_vector<Complex>((hierarchySize + 1) * Param::N2, make_Complex(0.0, 0.0));
}

void initializeDeviceConstants()
{
	initDeviceConstants<<<1, 1>>>();
	cudaDeviceSynchronize();
}

} // namespace

//Hamiltonian and correlation operator are defined here
//If you want to change them, overwrite this function
void createSystem()
{
	int spinCount = initialize_detail::spinCountFromHilbertSize(Param::N);
	host_vector<double> couplings = initialize_detail::buildCouplingMatrix(
		spinCount,
		Param::JNaver,
		Param::IsSquare);

	copyDenseOperatorsToDevice(buildDenseOperators(couplings, spinCount));

#ifndef DYNAMIC_DENSE
	//if you use cuSPARSE, define Hamiltonian and correlation operator in sparse format
	copySparseOperatorsToDevice(buildSparseOperators(couplings, spinCount));
#endif
}

void setTemperatureDependence()
{
	host_vector<double> Nu = buildBathFrequencies();
	copyBathFrequenciesToDevice(Nu);
	initializeBathCoefficients(Nu);
}

void initialize()
{
	Param::Filename = buildDefaultSnapshotFilename();

	initializePsdData();
	setTemperatureDependence();
	createSystem();
	initializeCublas();
	initializeHierarchyStorage();
	initializeRhoAndBuffer();
	initializeDeviceConstants();
}
int getHierarchySize(int k,int n)
{
	return initialize_detail::hierarchySizeFor(k, n);
}


void createHierarchy(int j,int& n,const host_vector<int>& vec,host_vector< host_vector<int> >& target,int max)
{
	initialize_detail::appendHierarchyRows(j, Param::KMax + 1, n, vec, target, max);
}

void getHierarchyEdge(const host_vector< host_vector<int> >& hierarchy,host_vector< host_vector<int> >& result)
{
	initialize_detail::buildHierarchyEdges(hierarchy, result, hierarchySize, Param::KMax + 1);
}
