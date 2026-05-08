#include "Psd/Psd.h"
#include "Parameters.h"
#include "Matrixes.h"
#ifndef INITINC
#define INITINC

extern void setTemperatureDependence();
extern void initialize();
extern int getHierarchySize(int k,int n);
extern void createHierarchy(int j,int& n,const host_vector<int>& vec,host_vector< host_vector<int> >& target,int max);
extern void getHierarchyEdge(const host_vector< host_vector<int> >& hierarchy,host_vector< host_vector<int> >& result);

#endif
