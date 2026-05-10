#include "library/legacy_runtime_session.h"

#include "initialize.h"
#include "liouville.h"
#include "matrix_storage.h"
#include "parameters.h"

#include <cuda_runtime.h>
#include <stdexcept>
#include <thrust/copy.h>
#include <thrust/host_vector.h>

namespace helix::library {

namespace {

void releaseLegacyRuntimeStorage() noexcept
{
	try
	{
		clearLiouvilleStorage();
	}
	catch(...)
	{
	}

	try
	{
		clearMatrixStorage();
	}
	catch(...)
	{
	}

	if(cublasHandle != nullptr)
	{
		cublasDestroy(cublasHandle);
		cublasHandle = nullptr;
	}
}

} // namespace

LegacyRuntimeSession::LegacyRuntimeSession(LegacyRuntimeSessionConfig config)
	: config_(config)
{
}

LegacyRuntimeSession::~LegacyRuntimeSession() noexcept
{
	destroy();
}

void LegacyRuntimeSession::create()
{
	if(active_)
	{
		throw std::logic_error("LegacyRuntimeSession is already active");
	}

	previousIntegrationOrder_ = Param::IntegrationNum;
	previousStep_ = Param::Step;
	Param::IntegrationNum = config_.integrationOrder;
	Param::Step = config_.step;

	try
	{
		initialize();
		active_ = true;
	}
	catch(...)
	{
		releaseLegacyRuntimeStorage();
		destroy();
		restoreParameters();
		throw;
	}
}

void LegacyRuntimeSession::run_steps(std::size_t steps)
{
	requireActive();
	for(std::size_t step = 0; step < steps; ++step)
	{
		develop();
		cudaDeviceSynchronize();
	}
}

std::vector<std::complex<double>> LegacyRuntimeSession::reduced_density() const
{
	requireActive();
	if(dRho.size() < static_cast<std::size_t>(Param::N2))
	{
		throw std::logic_error("LegacyRuntimeSession reduced density is not initialized");
	}

	thrust::host_vector<Complex> hostDensity(Param::N2);
	thrust::copy_n(dRho.begin(), Param::N2, hostDensity.begin());

	std::vector<std::complex<double>> reducedDensity;
	reducedDensity.reserve(hostDensity.size());
	for(const auto& value : hostDensity)
	{
		reducedDensity.emplace_back(static_cast<double>(value.x), static_cast<double>(value.y));
	}
	return reducedDensity;
}

void LegacyRuntimeSession::destroy() noexcept
{
	if(!active_)
	{
		return;
	}

	releaseLegacyRuntimeStorage();
	restoreParameters();
	active_ = false;
}

bool LegacyRuntimeSession::active() const noexcept
{
	return active_;
}

void LegacyRuntimeSession::requireActive() const
{
	if(!active_)
	{
		throw std::logic_error("LegacyRuntimeSession is not active");
	}
}

void LegacyRuntimeSession::restoreParameters() noexcept
{
	Param::IntegrationNum = previousIntegrationOrder_;
	Param::Step = previousStep_;
}

bool legacyRuntimeStorageReleased()
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

} // namespace helix::library
