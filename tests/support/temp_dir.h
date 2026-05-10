#pragma once

#include <chrono>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

namespace helix::test {

class TempDir {
public:
	explicit TempDir(const std::string& prefix = "helix-test-")
	{
		const std::filesystem::path base = std::filesystem::temp_directory_path();
		const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();

		for(int attempt = 0; attempt < 100; attempt++)
		{
			std::filesystem::path candidate =
				base / (prefix + std::to_string(stamp) + "-" + std::to_string(attempt));
			std::error_code error;
			if(std::filesystem::create_directory(candidate, error))
			{
				path_ = candidate;
				return;
			}
		}

		throw std::runtime_error("failed to create temporary HELIX test directory");
	}

	~TempDir()
	{
		cleanup();
	}

	TempDir(const TempDir&) = delete;
	TempDir& operator=(const TempDir&) = delete;

	TempDir(TempDir&& other) noexcept
		: path_(std::move(other.path_))
	{
		other.path_.clear();
	}

	TempDir& operator=(TempDir&& other) noexcept
	{
		if(this != &other)
		{
			cleanup();
			path_ = std::move(other.path_);
			other.path_.clear();
		}
		return *this;
	}

	const std::filesystem::path& path() const
	{
		return path_;
	}

	std::string string() const
	{
		return path_.string();
	}

private:
	void cleanup() noexcept
	{
		if(path_.empty())
		{
			return;
		}

		std::error_code error;
		std::filesystem::remove_all(path_, error);
	}

	std::filesystem::path path_;
};

} // namespace helix::test
