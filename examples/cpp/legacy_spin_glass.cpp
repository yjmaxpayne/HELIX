#include <helix/helix.h>

#include <cstdlib>
#include <iostream>

int main()
{
	auto system = helix::examples::legacy_spin_glass_system();
	auto bath = helix::Bath::drude_lorentz_pade();
	auto hierarchy = helix::HierarchySpec::compiled_default(bath);

	helix::SolverOptions options;
	options.steps = 2;

	auto result = helix::HEOMSolver().run(system, hierarchy, options);
	if(!result.ok())
	{
		std::cerr << result.diagnostics.summary() << '\n';
		return EXIT_FAILURE;
	}

	const auto& shape = result.reduced_density_shape;
	if(result.times.size() != shape.count || shape.count != 1 || shape.rows == 0
		|| shape.cols != shape.rows || result.reduced_density.empty())
	{
		std::cerr << "unexpected result shape\n";
		return EXIT_FAILURE;
	}

	std::cout << "helix_cpp_example: steps=" << result.diagnostics.steps
			  << " time=" << result.times.front() << " reduced_density_shape=(" << shape.count
			  << "," << shape.rows << "," << shape.cols << ")\n";
	return EXIT_SUCCESS;
}
