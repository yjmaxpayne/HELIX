#include "Matrixes.h"
#include "Parameters.h"
#include "Initialize.h"
#include "Liouville.h"
#include "operators.h"
#include "HelixVersion.h"
#include "cuda_runtime.h"
#include "TypeDef.h"
#include "device_launch_parameters.h"
#include<thrust/transform.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#endif
#include <iostream>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <time.h>
#include <thread>
#include <vector>
#include <climits>
#include <cstdlib>
#include <cstring>

using namespace std;

Complex energyBefore;
Complex energy;
ofstream energyStream;
std::vector<std::thread> outputThreads;

namespace {
int readStepCount()
{
	const int defaultStepCount = 1000000;
	const char* envName = "HELIX_STEPS";
	const char* value = std::getenv(envName);
	if(value == nullptr || value[0] == '\0')
	{
		envName = "HEOM_STEPS";
		value = std::getenv(envName);
	}
	if(value == nullptr || value[0] == '\0')
	{
		return defaultStepCount;
	}

	char* end = nullptr;
	long parsed = std::strtol(value, &end, 10);
	if(*end != '\0' || parsed < 0 || parsed > INT_MAX)
	{
		cerr << "Ignoring invalid " << envName << "=" << value << endl;
		return defaultStepCount;
	}
	return static_cast<int>(parsed);
}
}

bool outputRho(const device_vector<Complex>& rho,ofstream& stream,double time)
{
	static host_vector<Complex> result(Param::N);
	static Complex one=make_Complex(1.0,0.0);
	static Complex zero=make_Complex(0.0,0.0);
	device_vector<Complex> tmp(Param::N,zero);
	static host_vector<Complex> h=dH;
	cublasScal(cublasHandle,Param::N,&zero,raw_pointer_cast(tmp.data()),1);
	cublasAxpy(cublasHandle,Param::N,&one,raw_pointer_cast(rho.data()),Param::N+1,raw_pointer_cast(tmp.data()),1);
	cudaDeviceSynchronize();
	result=tmp;

	energy=make_Complex(0.0,0.0);
	for(int i=0;i<Param::N;i++)
	{
		int index=i+Param::N*i;
		energy=make_Complex(energy.x+h[index].x*result[i].x,energy.y);
	}
	for(int i=0;i<Param::N;i++)
	{
		stream<<result[i].x<<" ";
	}
	energyStream<<setprecision(8)<<time<<" "<<energy.x<<endl;

	stream<<endl;
	return false;
}

void outputBinary(string path,host_vector<Complex>& rho)
{
	ofstream fout;
	fout.open(path, ios::out|ios::binary|ios::trunc);
	if (!fout) {
		cout << "Cannnot open the file";
	}

	for(int i=0;i<hierarchySize*Param::N2;i++){
		real x,y;
		x=rho[i].x;
		y=rho[i].y;
		fout.write(( char * )&(x),sizeof( real ) );
		fout.write(( char * )&(y),sizeof( real ) );
	}
	fout.close();
}

void outputBinaryAsync(string path,host_vector<Complex>& rho)
{
	outputThreads.emplace_back([path,rho]() mutable { outputBinary(path,rho); });
}

void waitForOutputThreads()
{
	for(std::thread& t : outputThreads)
	{
		if(t.joinable())
		{
			t.join();
		}
	}
	outputThreads.clear();
}

int main(int argc, char** argv)
{
	if(argc == 2 && (std::strcmp(argv[1], "--version") == 0 || std::strcmp(argv[1], "-V") == 0))
	{
		cout << "HELIX " << HELIX_VERSION << endl;
		return 0;
	}

	initialize();
	
	float cuTime=0.0f;
	cudaEvent_t start,stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	
	clock_t startTime, endTime;
	int stepnum=readStepCount();
	ofstream output;
	energyStream=ofstream("outputEnergy.txt");
	int logCutNum=Param::OutputNum*1000;
	
	host_vector<Complex> rhoTmp=dRho;
	cudaEventRecord(start,0);
	startTime = clock();
	double secBefore=-10;
	double time=0.0;
	for (int i = (Param::SnapShotNum>=0?Param::SnapShotNum*logCutNum:0); i < stepnum;i++)
	{
		endTime = clock();
		double sec=(double)(endTime - startTime) / CLOCKS_PER_SEC;
		if(i%Param::OutputNum==0)
		{
			if(i%logCutNum==0)
			{
				int outnum=i/logCutNum;
				output.close();
				std::stringstream sss;
				sss<<"output_rho";
				sss<<outnum;
				sss<<".txt";
				
				output.open(sss.str(),ios::out);

				std::stringstream ssss;
				ssss<<"snapshot_rho";
				ssss<<outnum;
				ssss<<".dat";

				rhoTmp=dRho;
				outputBinaryAsync(ssss.str(),rhoTmp);
			}
			if(outputRho(dRho,output,time))
			{
				break;
			}

			energyBefore=energy;
		}
		/*
		//When you change condition such as temperature in progress, you must call setTemperatureDependence
		if(i==10000)
		{
			outputBinaryAsync(Param::Filename,rhoTmp);
			Param::Betah=10.0;
			Param::Step=0.01;
			Param::IntegrationNum=4;
			setTemperatureDependence();
		}*/

		if(sec-secBefore>0.5)
		{
			cout<<"\r"<<i<<"steps done. Time : "<<time<<"   "<<sec<<"sec."<<"  E:"<<energy.x<<"    ";
			secBefore=sec;
		}
		time+=Param::Step;
		develop();
		
		
	}
    cudaEventRecord(stop,0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&cuTime, start,stop);

	outputRho(dRho,output,time);
	output.close();
	output=ofstream("output.txt");
	output<<(stepnum > 0 ? cuTime/stepnum : 0.0f);
	output.close();
	energyStream.close();
	waitForOutputThreads();
	clearLiouvilleStorage();
	clearMatrixStorage();
	cublasDestroy(cublasHandle);
}
