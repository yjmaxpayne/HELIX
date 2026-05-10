#include "eigenvalues.h"

#include <algorithm>
#include <cmath>

namespace {

inline double& at(thrust::host_vector<double>& matrix, int row, int column, int size)
{
	return matrix[row + column * size];
}

inline double at(const thrust::host_vector<double>& matrix, int row, int column, int size)
{
	return matrix[row + column * size];
}

double offDiagonalNorm(const thrust::host_vector<double>& matrix, int size)
{
	double norm = 0.0;
	for(int column = 0; column < size; column++)
	{
		for(int row = column + 1; row < size; row++)
		{
			norm += std::abs(at(matrix, row, column, size));
		}
	}
	return norm;
}

void largestOffDiagonal(const thrust::host_vector<double>& matrix, int size, int& row, int& column)
{
	row = 1;
	column = 0;
	double maxValue = std::abs(at(matrix, row, column, size));

	for(int currentColumn = 0; currentColumn < size; currentColumn++)
	{
		for(int currentRow = currentColumn + 1; currentRow < size; currentRow++)
		{
			const double value = std::abs(at(matrix, currentRow, currentColumn, size));
			if(value > maxValue)
			{
				maxValue = value;
				row = currentRow;
				column = currentColumn;
			}
		}
	}
}

void rotate(thrust::host_vector<double>& matrix, int size, int p, int q)
{
	const double app = at(matrix, p, p, size);
	const double aqq = at(matrix, q, q, size);
	const double apq = at(matrix, p, q, size);
	if(apq == 0.0)
	{
		return;
	}

	const double angle = 0.5 * std::atan2(2.0 * apq, aqq - app);
	const double cosine = std::cos(angle);
	const double sine = std::sin(angle);

	for(int k = 0; k < size; k++)
	{
		if(k == p || k == q)
		{
			continue;
		}

		const double akp = at(matrix, k, p, size);
		const double akq = at(matrix, k, q, size);
		const double nextKp = cosine * akp - sine * akq;
		const double nextKq = sine * akp + cosine * akq;

		at(matrix, k, p, size) = nextKp;
		at(matrix, p, k, size) = nextKp;
		at(matrix, k, q, size) = nextKq;
		at(matrix, q, k, size) = nextKq;
	}

	at(matrix, p, p, size) = cosine * cosine * app - 2.0 * sine * cosine * apq + sine * sine * aqq;
	at(matrix, q, q, size) = sine * sine * app + 2.0 * sine * cosine * apq + cosine * cosine * aqq;
	at(matrix, p, q, size) = 0.0;
	at(matrix, q, p, size) = 0.0;
}

} // namespace

bool getEigval(int N,thrust::host_vector<double>& matrix)
{
	if(N <= 0 || matrix.size() < static_cast<size_t>(N * N))
	{
		return false;
	}

	constexpr double tolerance = 1.0e-14;
	const int maxSweeps = std::max(16, 100 * N * N);
	double residual = offDiagonalNorm(matrix, N);
	for(int sweep = 0; sweep < maxSweeps && residual > tolerance; sweep++)
	{
		int row = 0;
		int column = 1;
		largestOffDiagonal(matrix, N, row, column);
		rotate(matrix, N, column, row);
		residual = offDiagonalNorm(matrix, N);
	}

	if(residual > tolerance)
	{
		return false;
	}

	for(int column = 0; column < N; column++)
	{
		for(int row = 0; row < N; row++)
		{
			if(row != column)
			{
				at(matrix, row, column, N) = 0.0;
			}
		}
	}

	return true;
}
