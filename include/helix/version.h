#pragma once

#include <helix/version_config.h>

namespace helix {

inline constexpr const char* versionString() noexcept
{
	return HELIX_VERSION;
}

inline constexpr int versionMajor() noexcept
{
	return HELIX_VERSION_MAJOR;
}

inline constexpr int versionMinor() noexcept
{
	return HELIX_VERSION_MINOR;
}

inline constexpr int versionPatch() noexcept
{
	return HELIX_VERSION_PATCH;
}

inline constexpr const char* versionSource() noexcept
{
	return HELIX_VERSION_SOURCE;
}

const char* runtimeVersion() noexcept;

} // namespace helix
