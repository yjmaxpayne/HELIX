// M3.2 H-3.2.1 mechanism microtest: cudaEventRecord + cudaStreamWaitEvent
// fan-in / fan-out topology synchronizes N owned streams without a host-side
// device sync, matching the pattern used in src/liouville.cu's
// sparseStreamFanInToZero / sparseStreamFanOutFromZero helpers.

#include "support/assert.h"

#include <cstddef>
#include <cstdint>
#include <cuda_runtime.h>
#include <vector>

namespace {

constexpr int kStreamCount = 4;
constexpr std::size_t kBytes = 256;

// Each stream copies its src buffer into a shared dst region, then a
// rendezvous stream fans-in via events and validates that all four copies
// settled before the rendezvous-stream sees them.
void testFanInRendezvous(helix::test::Reporter& test)
{
	std::vector<cudaStream_t> streams(kStreamCount, nullptr);
	std::vector<cudaEvent_t> events(kStreamCount, nullptr);
	for(int i = 0; i < kStreamCount; ++i)
	{
		test.expect(cudaStreamCreate(&streams[i]) == cudaSuccess, "create per-hierarchy stream");
		test.expect(cudaEventCreateWithFlags(&events[i], cudaEventDisableTiming) == cudaSuccess, "create per-stream event");
	}

	std::vector<std::uint32_t*> deviceSrc(kStreamCount, nullptr);
	std::uint32_t* deviceDst = nullptr;
	test.expect(cudaMalloc(&deviceDst, kBytes * kStreamCount) == cudaSuccess, "alloc dst");
	for(int i = 0; i < kStreamCount; ++i)
	{
		test.expect(cudaMalloc(&deviceSrc[i], kBytes) == cudaSuccess, "alloc src[i]");
	}

	std::vector<std::vector<std::uint32_t>> hostSrc(kStreamCount, std::vector<std::uint32_t>(kBytes / sizeof(std::uint32_t)));
	for(int i = 0; i < kStreamCount; ++i)
	{
		for(std::size_t j = 0; j < hostSrc[i].size(); ++j)
		{
			hostSrc[i][j] = static_cast<std::uint32_t>(0xA5A50000u | (i << 8) | (j & 0xFFu));
		}
		test.expect(
			cudaMemcpyAsync(deviceSrc[i], hostSrc[i].data(), kBytes, cudaMemcpyHostToDevice, streams[i]) == cudaSuccess,
			"seed src[i] async");
	}

	for(int i = 0; i < kStreamCount; ++i)
	{
		test.expect(
			cudaMemcpyAsync(deviceDst + (i * kBytes / sizeof(std::uint32_t)),
				deviceSrc[i], kBytes, cudaMemcpyDeviceToDevice, streams[i]) == cudaSuccess,
			"per-stream copy src[i]->dst[i]");
	}

	// Fan-in to streams[0]: streams[0] waits all peer events.
	for(int i = 1; i < kStreamCount; ++i)
	{
		test.expect(cudaEventRecord(events[i], streams[i]) == cudaSuccess, "record peer event");
		test.expect(cudaStreamWaitEvent(streams[0], events[i], 0) == cudaSuccess, "rendezvous waits peer");
	}

	test.expect(cudaStreamSynchronize(streams[0]) == cudaSuccess, "rendezvous drains");

	std::vector<std::uint32_t> hostDst(kBytes * kStreamCount / sizeof(std::uint32_t), 0u);
	test.expect(
		cudaMemcpy(hostDst.data(), deviceDst, kBytes * kStreamCount, cudaMemcpyDeviceToHost) == cudaSuccess,
		"read dst");

	bool allMatch = true;
	for(int i = 0; i < kStreamCount; ++i)
	{
		for(std::size_t j = 0; j < hostSrc[i].size(); ++j)
		{
			if(hostDst[i * hostSrc[i].size() + j] != hostSrc[i][j])
			{
				allMatch = false;
				break;
			}
		}
		if(!allMatch) break;
	}
	test.expect(allMatch, "fan-in completes all peer writes before rendezvous drain");

	for(int i = 0; i < kStreamCount; ++i)
	{
		cudaFree(deviceSrc[i]);
		cudaEventDestroy(events[i]);
		cudaStreamDestroy(streams[i]);
	}
	cudaFree(deviceDst);
}

} // namespace

int main()
{
	helix::test::Reporter test;
	testFanInRendezvous(test);
	return test.finish("event_based_sync microtests (M3.2 H-3.2.1)");
}
