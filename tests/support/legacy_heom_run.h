#pragma once

#include "initialize.h"
#include "liouville.h"
#include "matrix_storage.h"
#include "parameters.h"

#include <cuda_runtime.h>
#include <stdexcept>
#include <thrust/copy.h>
#include <thrust/host_vector.h>

namespace helix::test {

struct HeomContextConfig
{
	int integrationOrder = 1;
	int stepCount = 1;
	double step = Param::Step;
};

class LegacyHeomRun
{
public:
	explicit LegacyHeomRun(const HeomContextConfig& config)
		: config_(config)
	{
	}

	~LegacyHeomRun()
	{
		destroy();
	}

	LegacyHeomRun(const LegacyHeomRun&) = delete;
	LegacyHeomRun& operator=(const LegacyHeomRun&) = delete;

	void create()
	{
		if(active_)
		{
			throw std::logic_error("LegacyHeomRun is already active");
		}

		previousIntegrationOrder_ = Param::IntegrationNum;
		previousStep_ = Param::Step;
		Param::IntegrationNum = config_.integrationOrder;
		Param::Step = config_.step;

		initialize();
		active_ = true;
	}

	void run()
	{
		requireActive();
		for(int step = 0; step < config_.stepCount; step++)
		{
			develop();
			cudaDeviceSynchronize();
		}
	}

	thrust::host_vector<Complex> reducedDensityBlock() const
	{
		requireActive();
		thrust::host_vector<Complex> reduced(Param::N2);
		thrust::copy_n(dRho.begin(), Param::N2, reduced.begin());
		return reduced;
	}

	void destroy()
	{
		if(!active_)
		{
			return;
		}

		clearLiouvilleStorage();
		clearMatrixStorage();
		if(cublasHandle != nullptr)
		{
			cublasDestroy(cublasHandle);
			cublasHandle = nullptr;
		}

		Param::IntegrationNum = previousIntegrationOrder_;
		Param::Step = previousStep_;
		active_ = false;
	}

private:
	void requireActive() const
	{
		if(!active_)
		{
			throw std::logic_error("LegacyHeomRun is not active");
		}
	}

	HeomContextConfig config_;
	bool active_ = false;
	int previousIntegrationOrder_ = Param::IntegrationNum;
	double previousStep_ = Param::Step;
};

inline bool legacyHeomStorageReleased()
{
	return cublasHandle == nullptr
		&& dH.empty()
		&& dV.empty()
		&& dNu.empty()
		&& dRho.empty()
		&& dHierarchies.empty()
		&& dKPhi.empty()
		&& dHierarchyEdge.empty()
		&& dBuffer.empty()
		&& dHElements.empty()
		&& dVElements.empty()
		&& dHColumns.empty()
		&& dVColumns.empty()
		&& dHOffsets.empty()
		&& dVOffsets.empty()
		&& KPhi.empty();
}

} // namespace helix::test
