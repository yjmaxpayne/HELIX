#include <helix/helix.h>
#include <helix/examples.h>

#include <cstring>
#include <iostream>

int main()
{
	static_assert(HELIX_VERSION_MAJOR >= 0, "generated version major is available");
	static_assert(helix::versionMajor() == HELIX_VERSION_MAJOR, "public version major matches generated header");

	if(helix::versionString()[0] == '\0')
	{
		std::cerr << "HELIX public version string is empty\n";
		return 1;
	}

	if(std::strcmp(helix::versionString(), helix::runtimeVersion()) != 0)
	{
		std::cerr << "HELIX runtime version differs from public version header\n";
		return 2;
	}

	auto system = helix::examples::legacy_spin_glass_system();
	if(system.kind != helix::SystemKind::LegacySpinGlass || !system.valid())
	{
		std::cerr << "HELIX legacy spin-glass example adapter is not public and valid\n";
		return 3;
	}

	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);
	if(!bath.validate_supported().ok() || !hierarchy.validate_supported().ok())
	{
		std::cerr << "HELIX compiled default bath/hierarchy adapters are not supported\n";
		return 4;
	}

	std::cout << "HELIX public header version: " << helix::versionString() << "\n";
	return 0;
}
