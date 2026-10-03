// M3.1 H-3.1.1 mechanism microtest: cudaMemcpyAsync on an owned non-zero
// stream copies device buffers correctly. This proves the primitive that
// develop()'s D2D copies were migrated to in src/liouville.cu (lines 478, 498
// region). End-to-end numerical equivalence is exercised by the full
// verify_examples gate; this test isolates the dispatch mechanism.

#include "support/assert.h"

#include <cstddef>
#include <cstdint>
#include <cuda_runtime.h>
#include <vector>

namespace {

constexpr std::size_t kElementCount = 1024;

void fillPattern(std::vector<std::uint32_t>& buffer)
{
	for(std::size_t i = 0; i < buffer.size(); ++i)
	{
		buffer[i] = static_cast<std::uint32_t>(0xC0FFEE00u + i);
	}
}

void testD2DCopyOnOwnedStream(helix::test::Reporter& test)
{
	const std::size_t byteCount = kElementCount * sizeof(std::uint32_t);

	cudaStream_t stream = nullptr;
	test.expect(cudaStreamCreate(&stream) == cudaSuccess, "creates owned cuda stream");
	test.expect(stream != nullptr, "owned stream handle is non-null (not the legacy default stream)");

	std::uint32_t* deviceSrc = nullptr;
	std::uint32_t* deviceDst = nullptr;
	test.expect(cudaMalloc(&deviceSrc, byteCount) == cudaSuccess, "allocates device src");
	test.expect(cudaMalloc(&deviceDst, byteCount) == cudaSuccess, "allocates device dst");

	std::vector<std::uint32_t> hostSrc(kElementCount);
	fillPattern(hostSrc);
	test.expect(
		cudaMemcpy(deviceSrc, hostSrc.data(), byteCount, cudaMemcpyHostToDevice) == cudaSuccess,
		"seeds device src with host pattern");

	// Mechanism under test: cudaMemcpyAsync DeviceToDevice on an owned
	// non-zero stream, mirroring the replacement at src/liouville.cu:478,498.
	test.expect(
		cudaMemcpyAsync(deviceDst, deviceSrc, byteCount, cudaMemcpyDeviceToDevice, stream)
			== cudaSuccess,
		"dispatches D2D copy on owned stream");
	test.expect(cudaStreamSynchronize(stream) == cudaSuccess, "owned stream drains");

	std::vector<std::uint32_t> hostDst(kElementCount, 0u);
	test.expect(
		cudaMemcpy(hostDst.data(), deviceDst, byteCount, cudaMemcpyDeviceToHost) == cudaSuccess,
		"reads back device dst");

	bool bitEqual = true;
	for(std::size_t i = 0; i < kElementCount; ++i)
	{
		if(hostDst[i] != hostSrc[i])
		{
			bitEqual = false;
			break;
		}
	}
	test.expect(bitEqual, "D2D copy preserves bit pattern on owned stream");

	cudaFree(deviceSrc);
	cudaFree(deviceDst);
	cudaStreamDestroy(stream);
}

} // namespace

int main()
{
	helix::test::Reporter test;
	testD2DCopyOnOwnedStream(test);
	return test.finish("develop_stream_ownership microtests (M3.1 H-3.1.1)");
}
