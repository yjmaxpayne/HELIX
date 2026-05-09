#ifndef INC_OPE
#define INC_OPE
#include "cuda_runtime.h"
#include "cuComplex.h"
#include "thrust/device_vector.h"
#include "thrust/iterator/constant_iterator.h"
#include "TypeDef.h"


__host__ __device__ static __inline__ Complex
operator-(const Complex &a) {
	return make_Complex(-a.x,-a.y);
}

__host__ __device__ static __inline__ Complex
operator-(const Complex &a,const Complex &b) {
	return a+(-b);
}

__host__ __device__ static __inline__ Complex
operator*(const Complex &a,const double &b) {
	return make_Complex(a.x*b,a.y*b);
}

__host__ __device__ static __inline__ Complex
operator*(const double &a,const Complex &b) {
	return b*a;
}

__host__ __device__ static __inline__ bool
operator==(const Complex &a,const Complex &b) {
	return a.x==b.x&&a.y==b.y;
}

__host__ __device__ static __inline__ Complex
	exp(Complex c)
{
	return make_Complex(
		exp(c.x)*cos(c.y),exp(c.x)*sin(c.y)
		);
}
#endif
