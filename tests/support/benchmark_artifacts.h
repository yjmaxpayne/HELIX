#pragma once

#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

namespace helix::test::benchmark {

constexpr const char* kBenchmarkJsonlFilename = "helix_benchmark.jsonl";
constexpr const char* kBenchmarkSummaryFilename = "helix_benchmark_summary.md";
constexpr const char* kBenchmarkNsightDirname = "nsight";

struct BenchmarkArtifactPaths {
	std::filesystem::path root;
	std::filesystem::path jsonl;
	std::filesystem::path summary;
	std::filesystem::path nsightDir;
};

inline BenchmarkArtifactPaths artifactPathsForRoot(std::filesystem::path root)
{
	BenchmarkArtifactPaths paths;
	paths.root = std::move(root);
	paths.jsonl = paths.root / kBenchmarkJsonlFilename;
	paths.summary = paths.root / kBenchmarkSummaryFilename;
	paths.nsightDir = paths.root / kBenchmarkNsightDirname;
	return paths;
}

inline std::filesystem::path resolveArtifactRoot(const char* envValue, const std::filesystem::path& defaultRoot)
{
	if(envValue != nullptr && envValue[0] != '\0')
	{
		return std::filesystem::absolute(std::filesystem::path(envValue)).lexically_normal();
	}
	return std::filesystem::absolute(defaultRoot).lexically_normal();
}

inline void ensureArtifactDirectories(const BenchmarkArtifactPaths& paths)
{
	std::filesystem::create_directories(paths.root);
	std::filesystem::create_directories(paths.nsightDir);
}

inline bool hasPrefix(const std::string& value, const char* prefix)
{
	return value.rfind(prefix, 0) == 0;
}

inline bool isLegacyOutputName(const std::filesystem::path& path)
{
	const std::string name = path.filename().string();
	return name == "outputEnergy.txt"
		|| name == "output.txt"
		|| (hasPrefix(name, "output_rho") && path.extension() == ".txt")
		|| (hasPrefix(name, "snapshot_rho") && path.extension() == ".dat");
}

inline bool isBenchmarkArtifactName(const std::filesystem::path& path)
{
	const std::string name = path.filename().string();
	return name == kBenchmarkJsonlFilename || name == kBenchmarkSummaryFilename;
}

inline bool isPathInside(const std::filesystem::path& path, const std::filesystem::path& root)
{
	std::error_code pathError;
	std::error_code rootError;
	auto normalizedPath = std::filesystem::weakly_canonical(path, pathError);
	auto normalizedRoot = std::filesystem::weakly_canonical(root, rootError);
	if(pathError)
	{
		normalizedPath = std::filesystem::absolute(path).lexically_normal();
	}
	if(rootError)
	{
		normalizedRoot = std::filesystem::absolute(root).lexically_normal();
	}

	const auto relative = normalizedPath.lexically_relative(normalizedRoot);
	if(relative.empty())
	{
		return normalizedPath == normalizedRoot;
	}

	const auto first = *relative.begin();
	return first != "..";
}

inline std::vector<std::filesystem::path> findMatchingFiles(const std::filesystem::path& directory,
	bool (*predicate)(const std::filesystem::path&))
{
	std::vector<std::filesystem::path> matches;
	std::error_code error;
	if(!std::filesystem::exists(directory, error))
	{
		return matches;
	}

	std::filesystem::recursive_directory_iterator entry(
		directory,
		std::filesystem::directory_options::skip_permission_denied,
		error);
	const std::filesystem::recursive_directory_iterator end;
	while(!error && entry != end)
	{
		if(entry->is_regular_file(error) && predicate(entry->path()))
		{
			matches.push_back(entry->path());
		}
		error.clear();
		entry.increment(error);
	}
	return matches;
}

inline std::vector<std::filesystem::path> findLegacyOutputs(const std::filesystem::path& directory)
{
	return findMatchingFiles(directory, isLegacyOutputName);
}

inline std::vector<std::filesystem::path> findMisplacedBenchmarkArtifacts(const std::filesystem::path& scanRoot,
	const std::filesystem::path& artifactRoot)
{
	std::vector<std::filesystem::path> misplaced;
	for(const auto& path : findMatchingFiles(scanRoot, isBenchmarkArtifactName))
	{
		if(!isPathInside(path, artifactRoot))
		{
			misplaced.push_back(path);
		}
	}
	return misplaced;
}

} // namespace helix::test::benchmark
