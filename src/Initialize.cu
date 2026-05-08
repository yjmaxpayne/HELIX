#include "Initialize.h"
#include "Liouville.h"
#include "TypeDef.h"
#include <fstream>
#include <iostream>
#include <sstream>

//Hamiltonian and correlation operator are defined here
//If you want to change them, overwrite this function
void createSystem()
{
	int n=(int)((log(Param::N) / log(2.0))+0.5);
	host_vector<double> js(n*n);
	double jNaver=Param::JNaver;
	if(n!=9)
	{
		for(int i=0;i<n;i++)
		{
			for(int j=0;j<n;j++)
			{
				if(i-j==-1||i-j==1)
				{
					js[i*n+j]=jNaver;
				}
				else
				{
					js[i*n+j]=0.0;
				}
			}
		}
	}
	else
	{
		if(!Param::IsSquare)
		{
			//triangular lattice
			js[0*n+1]=jNaver;
			js[0*n+7]=jNaver;
			js[1*n+0]=jNaver;
			js[1*n+7]=jNaver;
			js[1*n+2]=jNaver;
			js[1*n+8]=jNaver;
			js[2*n+1]=jNaver;
			js[2*n+3]=jNaver;
			js[2*n+8]=jNaver;
			js[3*n+2]=jNaver;
			js[3*n+4]=jNaver;
			js[3*n+5]=jNaver;
			js[3*n+8]=jNaver;
			js[4*n+3]=jNaver;
			js[4*n+5]=jNaver;
			js[5*n+4]=jNaver;
			js[5*n+6]=jNaver;
			js[5*n+3]=jNaver;
			js[5*n+8]=jNaver;
			js[6*n+5]=jNaver;
			js[6*n+7]=jNaver;
			js[6*n+8]=jNaver;
			js[7*n+6]=jNaver;
			js[7*n+0]=jNaver;
			js[7*n+1]=jNaver;
			js[7*n+8]=jNaver;
			js[8*n+1]=jNaver;
			js[8*n+2]=jNaver;
			js[8*n+3]=jNaver;
			js[8*n+5]=jNaver;
			js[8*n+6]=jNaver;
			js[8*n+7]=jNaver;
		}
		else
		{
			//square lattice
			js[0*n+1]=jNaver;
			js[0*n+7]=jNaver;
			js[1*n+0]=jNaver;
			js[1*n+2]=jNaver;
			js[1*n+8]=jNaver;
			js[2*n+1]=jNaver;
			js[2*n+3]=jNaver;
			js[3*n+2]=jNaver;
			js[3*n+4]=jNaver;
			js[3*n+8]=jNaver;
			js[4*n+3]=jNaver;
			js[4*n+5]=jNaver;
			js[5*n+4]=jNaver;
			js[5*n+6]=jNaver;
			js[5*n+8]=jNaver;
			js[6*n+5]=jNaver;
			js[6*n+7]=jNaver;
			js[7*n+6]=jNaver;
			js[7*n+0]=jNaver;
			js[7*n+8]=jNaver;
			js[8*n+1]=jNaver;
			js[8*n+3]=jNaver;
			js[8*n+5]=jNaver;
			js[8*n+7]=jNaver;
		}
	}
	host_vector<Complex> V=host_vector<Complex>(Param::N2,make_Complex(0.0,0.0));
	host_vector<Complex> H=host_vector<Complex>(Param::N2,make_Complex(0.0,0.0));

	for(int i=0;i<Param::N;i++)
	{
		host_vector<double> ns(n);
		double jTotal=0.0;

		for(int j=0;j<n;j++)
		{
			ns[j]=(((i>>j)&1)==1)?0.5*Param::Omega0:-0.5*Param::Omega0;
			jTotal+=ns[j];
		}
		
		V[i*Param::N+i]=make_Complex(Param::Dlong*jTotal,0.0);
		for(int j=0;j<n;j++)
		{
			for(int k=0;k<j;k++)
			{
				jTotal+=js[j*n+k]*ns[j]*ns[k];
			}
		}
		H[i*Param::N+i]=make_Complex(jTotal,0.0);
		for(int j=0;j<Param::N;j++)
		{
			int xx=i^j;
			if((xx==1)||(xx==2)||(xx==4)||(xx==8)||(xx==16)||(xx==32)||(xx==64)||(xx==128)||(xx==256)||(xx==512)||(xx==1024)||(xx==2048)||(xx==4096))
			{
				V[i*Param::N+j]=make_Complex(Param::Dtrans,0.0);
				H[i*Param::N+j]=make_Complex(Param::Delta,0.0);
			}
		}
		
	}
	
	dV=V;
	dH=H;

#ifndef DYNAMIC_DENSE
	//if you use cuSPARSE, define Hamiltonian and correlation operator in sparse format
	host_vector<Complex> VElements(Param::N*(n+1),make_Complex(0.0,0.0));
	host_vector<Complex> HElements(Param::N,make_Complex(0.0,0.0));
	host_vector<int> VColumns(Param::N*(n+1),0);
	host_vector<int> HColumns(Param::N,0);
	host_vector<int> VOffsets(Param::N+1,0);
	host_vector<int> HOffsets(Param::N+1,0);
	int VnonZeroNum=0;
	for(int i=0;i<Param::N;i++)
	{
		host_vector<double> ns(n);
		double jTotal=0.0;
		for(int j=0;j<n;j++)
		{
			ns[j]=(((i>>j)&1)==1)?0.5*Param::Omega0:-0.5*Param::Omega0;
			jTotal+=ns[j];
		}
		
		double vDiag=Param::Dlong*jTotal;
		for(int j=0;j<n;j++)
		{
			for(int k=0;k<j;k++)
			{
				jTotal+=js[j*n+k]*ns[j]*ns[k];
			}
		}
		for(int j=0;j<Param::N;j++)
		{
			if(i==j)
			{
				HElements[i]=make_Complex(jTotal,0.0);
				HColumns[i]=i;
				VElements[VnonZeroNum]=make_Complex(vDiag,0.0);
				VColumns[VnonZeroNum]=i;
				VnonZeroNum++;
			}
			int xx=i^j;
			if((xx==1)||(xx==2)||(xx==4)||(xx==8)||(xx==16)||(xx==32)||(xx==64)||(xx==128)||(xx==256))
			{
				VElements[VnonZeroNum]=make_Complex(Param::Dtrans,0.0);
				VColumns[VnonZeroNum]=j;
				VnonZeroNum++;
			}
		}
		VOffsets[i+1]=VnonZeroNum;
		HOffsets[i+1]=i+1;
	}
	dVElements=VElements;
	dVColumns=VColumns;
	dVOffsets=VOffsets;
	dHElements=HElements;
	dHColumns=HColumns;
	dHOffsets=HOffsets;
#endif
}

thrust::host_vector<double> poles,residues;
void setTemperatureDependence()
{
	host_vector<double> Nu=host_vector<double>(Param::KMax+1);
	Nu[0]=Param::Gamma;
	for(int i=1;i<=Param::KMax;i++)
	{
		//PSD
		double m=poles[i-1]/Param::Betah;
		Nu[i]=poles[i-1]/Param::Betah;
	}
	
	//MSD
	/*for(int i=1;i<=Param::KMax;i++)
	{
		Mu[i]= 2.0*i*Param::PI /Param::Betah;
		residues[i-1]=1.0;
	}*/
	

	dNu=device_vector<Complex>(Param::KMax+1);
	for(int i=0;i<=Param::KMax;i++)
	{
		dNu[i]=make_Complex(Nu[i],0.0);
	}

	

	double bhg_2=0.5*Param::Betah*Param::Gamma;
	double bhw=Param::Betah*Param::Omega0;
	double sigma= 1.0 - bhg_2 / tan(bhg_2) ;
	for(int i=1;i<=Param::KMax;i++)
	{
		sigma =sigma - 2.0*residues[i-1] * Param::Gamma*Param::Gamma/((Nu[i]*Nu[i])- Param::Gamma*Param::Gamma);
	}
	sigma*=(Param::Zeta / bhw);
	KXi=make_Complex(sigma,0.0);
	double counter=(Param::Zeta*bhg_2/bhw);
	KXiCounter=make_Complex(0,counter);
	KPhi=host_vector<Complex>(Param::KMax);
	
	for(int i=1;i<=Param::KMax;i++)
	{
		KPhi[i-1] = make_Complex(0.0,((Param::Zeta / bhw)*2.0*residues[i-1] * Param::Gamma*Param::Gamma/((Nu[i]*Nu[i])- Param::Gamma*Param::Gamma)));
	}
	dKPhi=KPhi;
	KThetaCommutate=make_Complex(0.0,Param::Betah*Param::Gamma*0.5/tan(Param::Betah*Param::Gamma*0.5)*Param::Zeta/bhw);
	KThetaAntiCommutate=make_Complex(Param::Betah*Param::Gamma*0.5*Param::Zeta/bhw,0.0);
}

void initialize()
{
	//define filename of default snapshot
	std::stringstream rhos;
				rhos<<"rho1_n9_j";
				rhos<<Param::JMax;
				rhos<<"_";
				rhos<<Param::JMax;
				rhos<<"_";
				rhos<<Param::KMax;
				rhos<<"_Jn";
				rhos<<(int)(Param::JNaver*10);
				if(Param::IsSquare)
				{
					rhos<<"_sq";
				}
#ifdef SINGLE
					rhos<<"_f";
#endif
				rhos<<".dat";
	Param::Filename=rhos.str();

	double R,T;
	getPsdPoleResidue(Param::KMax,false,NMinus1_N,poles,residues,R,T);
	setTemperatureDependence();
	createSystem();

	
	cublasStatus_t status = cublasCreate(&cublasHandle);
    if (status != CUBLAS_STATUS_SUCCESS)
    {
        fprintf(stderr, "!!!! CUBLAS initialization error\n");
        exit(status);
    }
	Complex one=make_Complex(1.0,0.0);
	Complex zero=make_Complex(0.0,0.0);

	hierarchySize=getHierarchySize(Param::KMax+1,Param::JMax);
	host_vector< host_vector<int> > hie(hierarchySize, host_vector<int>(Param::KMax+1));
	int n=0;
	createHierarchy(0,n,host_vector<int>(0),hie,Param::JMax);

	
	host_vector<int> Hierarchies((Param::KMax+1)*hierarchySize);
	for(int i=0;i<(Param::KMax+1)*hierarchySize;i++)
	{
		Hierarchies[i]=hie[i/(Param::KMax+1)][i%(Param::KMax+1)];
	}
	dHierarchies=Hierarchies;
	host_vector< host_vector<int> > edge(hierarchySize, host_vector<int>(Param::KMax*2+2));
	getHierarchyEdge(hie,edge);
	host_vector<int> Edges((Param::KMax*2+2)*hierarchySize);
	for(int i=0;i<(Param::KMax*2+2)*hierarchySize;i++)
	{
		Edges[i]=edge[i/(Param::KMax*2+2)][i%(Param::KMax*2+2)];
	}
	dHierarchyEdge=Edges;

	host_vector<Complex> Rho=host_vector<Complex>(Param::N2*(hierarchySize+1),make_Complex(0.0,0.0));
	
	//If you want to change the initial state, overwrite here
	if(Param::FromBoltzman)
	{
		/*
		double r=0.0;
		host_vector<Complex> H=dH;
		double b=Param::Betah;
		for(int i=0;i<Param::N;i++)
		{
			r+=exp(-b*H[i+i*Param::N].x);
		}

		for(int i=0;i<Param::N;i++)
		{
			Rho[i*Param::N+i] =make_Complex( 1.0*exp(-b*H[i+i*Param::N].x) /r+0.0/Param::N,0.0);
		}
	*/
		Rho[Param::N2-1]=make_Complex(1.0,0.0);
	}
	else
	{
		std::string name=Param::Filename;
		if(Param::SnapShotNum>=0)
		{
				std::stringstream ssss;
				ssss<<"snapshot_rho";
				ssss<<Param::SnapShotNum;
				ssss<<".dat";
				name=ssss.str();
		}
		std::ifstream fin(name, std::ios::in|std::ios::binary);
		if (!fin) {
			std::cout << "File "<<name<<" cannnot be opened";
			throw;
		}

		for(int i=0;i<hierarchySize*Param::N2;i++){
			real x,y;
			fin.read( ( char * ) &x, sizeof( real ) );
			fin.read( ( char * ) &y, sizeof( real ) );
			Rho[i]=make_Complex(x,y);
		}
		fin.close();  
	}
	dRho=Rho;

	host_vector<Complex> buffer((hierarchySize+1)*Param::N2,make_Complex(0.0,0.0));
	dBuffer=buffer;
	
	initDeviceConstants<<<1,1>>>();
	cudaDeviceSynchronize();
}
int getHierarchySize(int k,int n)
{
	if(k==1)
	{
		return n;
	}
	else
	{
		host_vector<int> numbers(n);	
		for(int i=0;i<n;i+=1)
		{
			numbers[i]=getHierarchySize(k-1,n-i);
		}
		return thrust::reduce(numbers.begin(),numbers.end(),0,thrust::plus<int>());
	}
}


void createHierarchy(int j,int& n,const host_vector<int>& vec,host_vector< host_vector<int> >& target,int max)
{
	if(j==Param::KMax+1)
	{
		target[n]=(vec);
		n++;
	}
	else if(j==0)
	{
		for(int i=0;i<max;i++)
		{
			host_vector<int> tmp(1);
			tmp[0]=i;
			createHierarchy(j+1,n,tmp,target,max);
		}
	}
	else
	{
		for(int i=0;i<max;i++)
		{
			int sum=(vec.size()>1)?reduce(vec.begin()+1,vec.end(),i):0;
			sum=sum+vec[0];
			if(sum<max)
			{
				host_vector<int> tmp(vec.size());
				for(int k=0;k<vec.size();k++)
				{
					tmp[k]=vec[k];
				}
				tmp.push_back(i);
				createHierarchy(j+1,n,tmp,target,max);
			}
		}
	}
}

void getHierarchyEdge(const host_vector< host_vector<int> >& hierarchy,host_vector< host_vector<int> >& result)
{
	for(int i=0;i<hierarchySize;i++)
	{
		for(int j=0;j<Param::KMax*2+2;j++)
		{
			result[i][j]=hierarchySize;
		}
	}
	host_vector<int> numOffset(Param::KMax+1);
	for(int i=0;i<hierarchySize;i++)
	{
		for(int j=0;j<Param::KMax+1;j++)
		{
			for(int k=0;k<Param::KMax+1;k++)
			{
				numOffset[k]=hierarchy[i][k]+((j==k)?1:0);
			}

			for(int k=0;k<hierarchySize;k++)
			{
				if(equal(numOffset.begin(),numOffset.end(),hierarchy[k].begin()))
				{
					result[i][j]=k;
					result[k][j+Param::KMax+1]=i;
					break;
				}
			}
		}
	}
}
