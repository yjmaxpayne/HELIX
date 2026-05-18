#include "library/legacy_runtime_session.h"

#include "initialize.h"
#include "library/result_extractor.h"
#include "liouville.h"
#include "matrix_storage.h"
#include "parameters.h"

#include <cuda_runtime.h>
#include <stdexcept>

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
	// M3.2 H-3.2.1 (extended scope): the per-step `cudaDeviceSynchronize()`
	// outer fence was a host-side convenience; the next develop() call
	// naturally serializes on the same developCopyStream, and host-side
	// readers (ResultExtractor / energy print) sync via their own D->H copy.
	// Removed so capture mode is not broken by a host-blocking fence between
	// the only API call the M2 spike makes inside cudaStreamBeginCapture.
	for(std::size_t step = 0; step < steps; ++step)
	{
		develop();
	}
}

std::vector<std::complex<double>> LegacyRuntimeSession::reduced_density() const
{
	requireActive();
	return ResultExtractor::final_reduced_density().values;
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
