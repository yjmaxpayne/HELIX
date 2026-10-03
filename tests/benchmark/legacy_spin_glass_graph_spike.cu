// M2 evidence-only CUDA Graph capture spike for HELIX v0.0.5 perf-tightening.
//
// Purpose: probe whether one steady iteration of the legacy spin-glass hot
// path can be captured into a `cudaGraph_t` and replayed. The current hot
// path uses `cudaDeviceSynchronize()` inside `develop()` and
// `getdRhoSparse()`; CUDA capture forbids host-side device synchronization in
// every capture mode. The expected outcome is therefore that all three
// capture modes (global / thread-local / relaxed) record a failure status,
// and the resulting JSONL becomes the evidence for the M2.4 production-
// landing dependency chain.
//
// This binary is registered as CTest `v005_cuda_graph_spike_gate` with label
// `benchmark`, and is intentionally NOT in the default test selector
// (`-LE "^(sanitizer|benchmark)$"` excludes it). See
// `.plan/research/v005-perf-tightening/program.md §3.2` for the design.

#include <helix/helix.h>
#include <helix/types.h>

#include <cuda_runtime.h>

#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

constexpr int kDevice = 0;

void requireCuda(cudaError_t status, const char* action)
{
	if(status != cudaSuccess)
	{
		throw std::runtime_error(std::string("Failed to ") + action + ": " + cudaGetErrorString(status));
	}
}

std::size_t envPositiveOrDefault(const char* key, std::size_t fallback)
{
	const char* raw = std::getenv(key);
	if(raw == nullptr || raw[0] == '\0')
	{
		return fallback;
	}
	char* end = nullptr;
	unsigned long long value = std::strtoull(raw, &end, 10);
	if(end == nullptr || *end != '\0' || value == 0)
	{
		return fallback;
	}
	return static_cast<std::size_t>(value);
}

std::string envOrDefault(const char* key, const char* fallback)
{
	const char* raw = std::getenv(key);
	if(raw == nullptr || raw[0] == '\0')
	{
		return std::string(fallback);
	}
	return std::string(raw);
}

helix::ContextOptions spikeContextOptions()
{
	helix::ContextOptions options;
	options.device = kDevice;
	return options;
}

struct CaptureProbe
{
	const char* modeName;
	cudaStreamCaptureMode mode;
	cudaError_t beginStatus;
	cudaError_t stepStatus; // captured from run_steps exception (if any)
	std::string stepError;
	cudaError_t endStatus;
	bool graphNonNull;
	double wallMs;
};

CaptureProbe runProbe(helix::Context& ctx, const char* modeName, cudaStreamCaptureMode mode)
{
	CaptureProbe probe{modeName, mode, cudaSuccess, cudaSuccess, {}, cudaSuccess, false, 0.0};

	cudaStream_t captureStream = nullptr;
	requireCuda(cudaStreamCreate(&captureStream), "create capture stream");

	const auto t0 = std::chrono::steady_clock::now();
	probe.beginStatus = cudaStreamBeginCapture(captureStream, mode);

	try
	{
		ctx.run_steps(1);
	}
	catch(const std::exception& exc)
	{
		probe.stepStatus = cudaErrorStreamCaptureUnsupported;
		probe.stepError = exc.what();
	}

	cudaGraph_t graph = nullptr;
	probe.endStatus = cudaStreamEndCapture(captureStream, &graph);
	const auto t1 = std::chrono::steady_clock::now();
	probe.wallMs = std::chrono::duration<double, std::milli>(t1 - t0).count();
	probe.graphNonNull = (graph != nullptr);

	if(graph != nullptr)
	{
		cudaGraphDestroy(graph);
	}
	cudaStreamDestroy(captureStream);

	// Capture failure may leave the device in an error state; drain it so the
	// next probe sees a clean slate.
	(void)cudaGetLastError();
	return probe;
}

std::string jsonEscape(const std::string& in)
{
	std::ostringstream out;
	for(const char c : in)
	{
		switch(c)
		{
			case '"': out << "\\\""; break;
			case '\\': out << "\\\\"; break;
			case '\n': out << "\\n"; break;
			case '\r': out << "\\r"; break;
			case '\t': out << "\\t"; break;
			default:
				if(static_cast<unsigned char>(c) < 0x20)
				{
					char buf[8];
					std::snprintf(buf, sizeof(buf), "\\u%04x", c);
					out << buf;
				}
				else
				{
					out << c;
				}
		}
	}
	return out.str();
}

void writeJsonl(const std::filesystem::path& path,
	const std::array<CaptureProbe, 3>& probes,
	std::size_t warmupSteps,
	bool anyCaptured,
	const cudaDeviceProp& deviceProperties,
	int driverVersion,
	int runtimeVersion)
{
	std::ostringstream rec;
	rec << "{";
	rec << "\"schema_version\":1,";
	rec << "\"experiment\":\"v005_cuda_graph_spike\",";
	rec << "\"warmup_steps\":" << warmupSteps << ",";
	rec << "\"device\":\"" << jsonEscape(deviceProperties.name) << "\",";
	rec << "\"cuda_capability\":\"sm_" << deviceProperties.major << deviceProperties.minor << "\",";
	rec << "\"cuda_runtime_version\":" << runtimeVersion << ",";
	rec << "\"cuda_driver_version\":" << driverVersion << ",";
	rec << "\"capture_modes\":[";
	bool first = true;
	for(const auto& probe : probes)
	{
		if(!first)
		{
			rec << ",";
		}
		first = false;
		rec << "{";
		rec << "\"mode\":\"" << probe.modeName << "\",";
		rec << "\"begin_status\":" << static_cast<int>(probe.beginStatus) << ",";
		rec << "\"begin_error\":\"" << jsonEscape(cudaGetErrorString(probe.beginStatus)) << "\",";
		rec << "\"step_status\":" << static_cast<int>(probe.stepStatus) << ",";
		rec << "\"step_error\":\"" << jsonEscape(probe.stepError) << "\",";
		rec << "\"end_status\":" << static_cast<int>(probe.endStatus) << ",";
		rec << "\"end_error\":\"" << jsonEscape(cudaGetErrorString(probe.endStatus)) << "\",";
		rec << "\"graph_non_null\":" << (probe.graphNonNull ? "true" : "false") << ",";
		rec << "\"wall_ms\":" << probe.wallMs;
		rec << "}";
	}
	rec << "],";
	rec << "\"any_mode_captured\":" << (anyCaptured ? "true" : "false") << ",";
	if(anyCaptured)
	{
		rec << "\"verdict\":\"capture_succeeded — at least one mode produced a non-null graph;"
		    << " H-M2.2/M2.3 replay+numeq probes deferred to a follow-up spike iteration\"";
	}
	else
	{
		rec << "\"verdict\":\"capture_blocked — all three modes failed;"
		    << " consistent with cudaDeviceSynchronize() inside develop()/getdRhoSparse()"
		    << " being forbidden inside cudaStreamBeginCapture per CUDA docs;"
		    << " production-landing dependency chain: event-based sync → runtime state ownership S1–S4"
		    << " → debug sync mode → graph capture\"";
	}
	rec << "}\n";

	std::ofstream out(path, std::ios::out | std::ios::trunc);
	if(!out.is_open())
	{
		throw std::runtime_error("could not open output JSONL: " + path.string());
	}
	out << rec.str();
}

} // namespace

int main()
{
	try
	{
		requireCuda(cudaSetDevice(kDevice), "select CUDA spike device");

		cudaDeviceProp deviceProperties{};
		requireCuda(cudaGetDeviceProperties(&deviceProperties, kDevice), "query CUDA device properties");
		int driverVersion = 0;
		int runtimeVersion = 0;
		requireCuda(cudaDriverGetVersion(&driverVersion), "query CUDA driver version");
		requireCuda(cudaRuntimeGetVersion(&runtimeVersion), "query CUDA runtime version");

		const std::size_t warmupSteps = envPositiveOrDefault("HELIX_BENCHMARK_WARMUP_STEPS", 10);
		const std::filesystem::path outputDir = envOrDefault("HELIX_BENCHMARK_OUTPUT_DIR",
			HELIX_BENCHMARK_DEFAULT_OUTPUT_DIR);
		std::filesystem::create_directories(outputDir);
		const std::filesystem::path jsonlPath = outputDir / "v005_cuda_graph_spike.jsonl";

		const helix::ContextOptions options = spikeContextOptions();
		helix::Context context(options);

		std::cerr << "[graph-spike] device=" << deviceProperties.name
		          << " sm_" << deviceProperties.major << deviceProperties.minor
		          << " cudart=" << runtimeVersion << " driver=" << driverVersion << "\n";
		std::cerr << "[graph-spike] running warmup=" << warmupSteps << " steps\n";
		context.run_steps(warmupSteps);
		requireCuda(cudaDeviceSynchronize(), "synchronize after warmup");

		std::cerr << "[graph-spike] probing capture modes: global / thread_local / relaxed\n";
		std::array<CaptureProbe, 3> probes = {
			runProbe(context, "global", cudaStreamCaptureModeGlobal),
			runProbe(context, "thread_local", cudaStreamCaptureModeThreadLocal),
			runProbe(context, "relaxed", cudaStreamCaptureModeRelaxed),
		};

		bool anyCaptured = false;
		for(const auto& probe : probes)
		{
			std::cerr << "[graph-spike] mode=" << probe.modeName
			          << " begin=" << cudaGetErrorString(probe.beginStatus)
			          << " end=" << cudaGetErrorString(probe.endStatus)
			          << " graph_non_null=" << (probe.graphNonNull ? "true" : "false")
			          << " wall_ms=" << probe.wallMs << "\n";
			if(probe.beginStatus == cudaSuccess && probe.endStatus == cudaSuccess && probe.graphNonNull)
			{
				anyCaptured = true;
			}
		}

		writeJsonl(jsonlPath, probes, warmupSteps, anyCaptured, deviceProperties, driverVersion, runtimeVersion);
		std::cerr << "[graph-spike] wrote " << jsonlPath << "\n";
		std::cerr << "[graph-spike] verdict=" << (anyCaptured ? "captured" : "capture_blocked") << "\n";

		context.destroy();
		return 0;
	}
	catch(const std::exception& exc)
	{
		std::cerr << "[graph-spike] FATAL: " << exc.what() << "\n";
		return 1;
	}
}
