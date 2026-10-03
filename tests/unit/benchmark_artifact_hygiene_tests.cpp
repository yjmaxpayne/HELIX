#include "support/assert.h"
#include "support/benchmark_artifacts.h"
#include "support/temp_dir.h"

#include <filesystem>
#include <fstream>
#include <vector>

namespace {

void writeFile(const std::filesystem::path& path)
{
	std::ofstream output(path);
	output << "test\n";
}

bool containsFilename(const std::vector<std::filesystem::path>& paths, const char* filename)
{
	for(const auto& path : paths)
	{
		if(path.filename() == filename)
		{
			return true;
		}
	}
	return false;
}

void test_output_root_policy(helix::test::Reporter& reporter)
{
	const auto defaultRoot = std::filesystem::path("/tmp/helix-default-benchmark");
	const auto envRoot = std::filesystem::path("/tmp/helix-env-benchmark");

	reporter.expect(helix::test::benchmark::resolveArtifactRoot(nullptr, defaultRoot) == defaultRoot,
		"unset HELIX_BENCHMARK_OUTPUT_DIR uses build-tree benchmark default");
	reporter.expect(helix::test::benchmark::resolveArtifactRoot("", defaultRoot) == defaultRoot,
		"empty HELIX_BENCHMARK_OUTPUT_DIR uses build-tree benchmark default");
	reporter.expect(helix::test::benchmark::resolveArtifactRoot(envRoot.string().c_str(), defaultRoot) == envRoot,
		"HELIX_BENCHMARK_OUTPUT_DIR overrides the build-tree benchmark default");
	const std::string relativeRoot = "relative-benchmark-root";
	reporter.expect(helix::test::benchmark::resolveArtifactRoot(relativeRoot.c_str(), defaultRoot)
			== std::filesystem::absolute(relativeRoot).lexically_normal(),
		"relative HELIX_BENCHMARK_OUTPUT_DIR is resolved before the runner changes working directory");

	const auto paths = helix::test::benchmark::artifactPathsForRoot(envRoot);
	reporter.expect(paths.root == envRoot, "artifact root is retained");
	reporter.expect(paths.jsonl == envRoot / "helix_benchmark.jsonl", "JSONL path lives under artifact root");
	reporter.expect(paths.summary == envRoot / "helix_benchmark_summary.md", "summary path lives under artifact root");
	reporter.expect(paths.nsightDir == envRoot / "nsight", "nsight artifact directory lives under artifact root");
}

void test_legacy_output_detection(helix::test::Reporter& reporter)
{
	helix::test::TempDir temp("helix-benchmark-hygiene-");
	writeFile(temp.path() / "outputEnergy.txt");
	writeFile(temp.path() / "output.txt");
	writeFile(temp.path() / "output_rho42.txt");
	writeFile(temp.path() / "snapshot_rho42.dat");
	writeFile(temp.path() / "helix_benchmark.jsonl");

	const auto legacyOutputs = helix::test::benchmark::findLegacyOutputs(temp.path());
	reporter.expect(legacyOutputs.size() == 4, "legacy HELIX output detection ignores benchmark artifacts");
	reporter.expect(containsFilename(legacyOutputs, "outputEnergy.txt"), "legacy detection catches outputEnergy.txt");
	reporter.expect(containsFilename(legacyOutputs, "output.txt"), "legacy detection catches output.txt");
	reporter.expect(containsFilename(legacyOutputs, "output_rho42.txt"), "legacy detection catches output_rho*.txt");
	reporter.expect(containsFilename(legacyOutputs, "snapshot_rho42.dat"), "legacy detection catches snapshot_rho*.dat");
}

void test_benchmark_artifact_containment(helix::test::Reporter& reporter)
{
	helix::test::TempDir scan("helix-benchmark-scan-");
	const auto artifactRoot = scan.path() / "artifact-root";
	const auto paths = helix::test::benchmark::artifactPathsForRoot(artifactRoot);
	std::filesystem::create_directories(paths.root);

	writeFile(paths.jsonl);
	writeFile(paths.summary);
	reporter.expect(helix::test::benchmark::findMisplacedBenchmarkArtifacts(scan.path(), paths.root).empty(),
		"JSONL and summary are accepted inside the artifact root");

	writeFile(scan.path() / "helix_benchmark.jsonl");
	const auto misplaced = helix::test::benchmark::findMisplacedBenchmarkArtifacts(scan.path(), paths.root);
	reporter.expect(misplaced.size() == 1, "benchmark JSONL outside artifact root is reported");
	reporter.expect(containsFilename(misplaced, "helix_benchmark.jsonl"),
		"misplaced artifact report names helix_benchmark.jsonl");
}

} // namespace

int main()
{
	helix::test::Reporter reporter;

	test_output_root_policy(reporter);
	test_legacy_output_detection(reporter);
	test_benchmark_artifact_containment(reporter);

	return reporter.finish("benchmark_artifact_hygiene_tests");
}
