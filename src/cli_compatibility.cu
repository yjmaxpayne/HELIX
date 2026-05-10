#include "cli_compatibility.h"

#include "complex_operators.h"
#include "initialize.h"
#include "library/energy_observable.h"
#include "liouville.h"
#include "matrix_storage.h"
#include "parameters.h"

#include <helix/version_config.h>

#include <cuda_runtime.h>
#include <thrust/device_ptr.h>

#include <complex>
#include <cstdlib>
#include <ctime>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace helix::cli {
namespace {

std::vector<std::complex<double>> toStdComplexVector(const host_vector<Complex>& values)
{
	std::vector<std::complex<double>> converted;
	converted.reserve(values.size());
	for(const auto& value : values)
	{
		converted.emplace_back(static_cast<double>(value.x), static_cast<double>(value.y));
	}
	return converted;
}

host_vector<Complex> copyDensityDiagonal(const device_vector<Complex>& rho)
{
	static const Complex one = make_Complex(1.0, 0.0);
	static const Complex zero = make_Complex(0.0, 0.0);

	device_vector<Complex> tmp(Param::N, zero);
	cublasScal(cublasHandle, Param::N, &zero, thrust::raw_pointer_cast(tmp.data()), 1);
	cublasAxpy(cublasHandle,
		Param::N,
		&one,
		thrust::raw_pointer_cast(rho.data()),
		Param::N + 1,
		thrust::raw_pointer_cast(tmp.data()),
		1);
	cudaDeviceSynchronize();

	host_vector<Complex> result(Param::N);
	result = tmp;
	return result;
}

class LegacyCliWriter {
public:
	LegacyCliWriter()
		: energyStream_("outputEnergy.txt")
	{
		const host_vector<Complex> hamiltonian = dH;
		hamiltonian_ = toStdComplexVector(hamiltonian);
	}

	bool writeRho(const device_vector<Complex>& rho, std::ofstream& stream, double time)
	{
		const host_vector<Complex> densityDiagonal = copyDensityDiagonal(rho);
		const auto standardDiagonal = toStdComplexVector(densityDiagonal);
		const double energyValue = library::energyFromDensityDiagonal(
			hamiltonian_,
			standardDiagonal,
			static_cast<std::size_t>(Param::N));
		currentEnergy_ = make_Complex(energyValue, 0.0);

		for(int i = 0; i < Param::N; i++)
		{
			stream << densityDiagonal[i].x << " ";
		}
		energyStream_ << std::setprecision(8) << time << " " << currentEnergy_.x << std::endl;

		stream << std::endl;
		return false;
	}

	void writeBinaryAsync(std::string path, host_vector<Complex> rho)
	{
		outputThreads_.emplace_back([path = std::move(path), rho = std::move(rho)]() {
			writeBinary(path, rho);
		});
	}

	void waitForOutputThreads()
	{
		for(std::thread& thread : outputThreads_)
		{
			if(thread.joinable())
			{
				thread.join();
			}
		}
		outputThreads_.clear();
	}

	void closeEnergyStream()
	{
		energyStream_.close();
	}

	const Complex& currentEnergy() const noexcept
	{
		return currentEnergy_;
	}

private:
	static void writeBinary(const std::string& path, const host_vector<Complex>& rho)
	{
		std::ofstream output(path, std::ios::out | std::ios::binary | std::ios::trunc);
		if(!output)
		{
			std::cout << "Cannnot open the file";
		}

		for(int i = 0; i < hierarchySize * Param::N2; i++)
		{
			const real x = rho[i].x;
			const real y = rho[i].y;
			output.write(reinterpret_cast<const char*>(&x), sizeof(real));
			output.write(reinterpret_cast<const char*>(&y), sizeof(real));
		}
	}

	std::ofstream energyStream_;
	std::vector<std::complex<double>> hamiltonian_;
	std::vector<std::thread> outputThreads_;
	Complex currentEnergy_ = make_Complex(0.0, 0.0);
};

bool versionRequested(int argc, char** argv)
{
	return argc == 2 && (std::strcmp(argv[1], "--version") == 0 || std::strcmp(argv[1], "-V") == 0);
}

std::string outputRhoPath(int outputIndex)
{
	std::stringstream path;
	path << "output_rho" << outputIndex << ".txt";
	return path.str();
}

std::string snapshotPath(int outputIndex)
{
	std::stringstream path;
	path << "snapshot_rho" << outputIndex << ".dat";
	return path.str();
}

class LegacyCliRunner {
public:
	int run(int argc, char** argv)
	{
		if(versionRequested(argc, argv))
		{
			std::cout << "HELIX " << HELIX_VERSION << std::endl;
			return 0;
		}

		initialize();

		float cuTime = 0.0f;
		cudaEvent_t start, stop;
		cudaEventCreate(&start);
		cudaEventCreate(&stop);

		const std::clock_t startTime = std::clock();
		const int stepnum = readStepCount();
		const int logCutNum = Param::OutputNum * 1000;

		LegacyCliWriter writer;
		std::ofstream output;
		host_vector<Complex> rhoTmp = dRho;

		cudaEventRecord(start, 0);
		double secBefore = -10.0;
		double time = 0.0;
		for(int i = (Param::SnapShotNum >= 0 ? Param::SnapShotNum * logCutNum : 0); i < stepnum; i++)
		{
			const std::clock_t endTime = std::clock();
			const double sec = static_cast<double>(endTime - startTime) / CLOCKS_PER_SEC;
			if(i % Param::OutputNum == 0)
			{
				if(i % logCutNum == 0)
				{
					const int outnum = i / logCutNum;
					output.close();
					output.open(outputRhoPath(outnum), std::ios::out);

					rhoTmp = dRho;
					writer.writeBinaryAsync(snapshotPath(outnum), rhoTmp);
				}
				if(writer.writeRho(dRho, output, time))
				{
					break;
				}
			}

			if(sec - secBefore > 0.5)
			{
				std::cout << "\r" << i << "steps done. Time : " << time << "   " << sec
						  << "sec." << "  E:" << writer.currentEnergy().x << "    ";
				secBefore = sec;
			}
			time += Param::Step;
			develop();
		}
		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&cuTime, start, stop);

		writer.writeRho(dRho, output, time);
		output.close();
		output.open("output.txt", std::ios::out);
		output << (stepnum > 0 ? cuTime / stepnum : 0.0f);
		output.close();
		writer.closeEnergyStream();
		writer.waitForOutputThreads();
		clearLiouvilleStorage();
		clearMatrixStorage();
		cublasDestroy(cublasHandle);
		return 0;
	}
};

} // namespace

int readStepCount()
{
	StepCountInputs inputs;
	inputs.helixSteps = std::getenv("HELIX_STEPS");
	inputs.heomSteps = std::getenv("HEOM_STEPS");
	return readStepCount(inputs, std::cerr);
}

int runCompatibilityCli(int argc, char** argv)
{
	return LegacyCliRunner{}.run(argc, argv);
}

} // namespace helix::cli
