#include "Eigval.h"
#include "Psd.h"
#include "thrust/sort.h"

#include <cmath>

inline int b(const int m,const bool isFermi)
{
	return (2*m+(isFermi?-1:1));
}

bool getPsdPoleResidue(const int n,const bool isFermi,const PadeType type,
					thrust::host_vector<double>& poles,thrust::host_vector<double>& residues,double& R,double& T)
{
	T=0.0;
	R=0.0;
	int nMatrix=2*n+(int)type;
	thrust::host_vector<double> matrix(nMatrix*nMatrix);
	poles=thrust::host_vector<double>(n+1);
	residues=thrust::host_vector<double>(n+1);

	if(type==NPlus1_N){throw;}
	if(type==N_N)R=0.25/(n+1.00)/b(n+1,isFermi);
	for(int x=0;x<nMatrix;x++)
	{
		for(int y=0;y<nMatrix;y++)
		{
			if(abs(x-y)==1)
			{
				matrix[x*nMatrix+y]=1.0/sqrt(1.0*b(x+1,isFermi)*b(y+1,isFermi));
			}
			else
			{
				matrix[x*nMatrix+y]=0.0;
			}
		}
	}
	if(!getEigval(nMatrix,matrix))
	{
		return false;
	}
	thrust::host_vector<double> eig(nMatrix);
	for(int x=0;x<nMatrix;x++)
	{
		eig[x]=matrix[x*nMatrix+x];
	}
	thrust::sort(eig.begin(),eig.end());
	for(int i=0;i<n;i++)
	{
		poles[i] = 2.0/eig[nMatrix-1-i];
	}

	nMatrix--;
	for(int x=0;x<nMatrix;x++)
	{
		for(int y=0;y<nMatrix;y++)
		{
			if(abs(x-y)==1)
			{
				matrix[x*nMatrix+y]=1.0/sqrt(1.0*b(x+2,isFermi)*b(y+2,isFermi));
			}
			else
			{
				matrix[x*nMatrix+y]=0.0;
			}
		}
	}
	if(!getEigval(nMatrix,matrix))
	{
		return false;
	}
	for(int x=0;x<nMatrix;x++)
	{
		eig[x]=matrix[x*nMatrix+x];
	}

	thrust::sort(eig.begin(),eig.begin()+nMatrix);
	int m=nMatrix/2;
	thrust::host_vector<double> xi(n);
	thrust::host_vector<double> zeta(m);
	for(int i=0;i<n;i++)
	{
		xi[i]=poles[i]*poles[i];
	}
	for(int i=0;i<m;i++)
	{
		zeta[i]=(4.0/(eig[nMatrix-1-i]*eig[nMatrix-1-i]));
	}
	double scaling=n*b(n+1,isFermi);
	if(type==N_N)scaling=1.0/(4.0*(n+1)*b(n+1,isFermi));

	for(int i=0;i<n;i++)
	{
		double tmp=0;
		if(type==N_N)
		{
			tmp=0.5*scaling*(zeta[i]-xi[i]);
		}
		else
		{
			if(i==n-1){tmp=0.5*scaling;}
			else{tmp=0.5*scaling*(zeta[i]-xi[i])/(xi[n-1]-xi[i]);}
		}
		for(int j=0;j<m;j++)
		{
			if(i==j){continue;}
			tmp*=(zeta[j]-xi[i])/(xi[j]-xi[i]);
		}
		residues[i]=tmp;
	}

	return true;
}
