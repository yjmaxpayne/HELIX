if(NOT DEFINED HELIX_EXECUTABLE)
	message(FATAL_ERROR "HELIX_EXECUTABLE is required")
endif()
if(NOT DEFINED HELIX_VERSION_STRING)
	message(FATAL_ERROR "HELIX_VERSION_STRING is required")
endif()
if(NOT DEFINED HELIX_ENERGY_COMPARE)
	message(FATAL_ERROR "HELIX_ENERGY_COMPARE is required")
endif()
if(NOT DEFINED HELIX_REFERENCE_ENERGY)
	message(FATAL_ERROR "HELIX_REFERENCE_ENERGY is required")
endif()
if(NOT DEFINED HELIX_CLI_ROOT)
	message(FATAL_ERROR "HELIX_CLI_ROOT is required")
endif()

function(assert_version flag)
	execute_process(
		COMMAND "${HELIX_EXECUTABLE}" "${flag}"
		RESULT_VARIABLE version_result
		OUTPUT_VARIABLE version_stdout
		ERROR_VARIABLE version_stderr
		TIMEOUT 30
	)
	if(NOT version_result EQUAL 0)
		message(FATAL_ERROR
			"helix ${flag} failed\n"
			"stdout:\n${version_stdout}\n"
			"stderr:\n${version_stderr}"
		)
	endif()

	string(STRIP "${version_stdout}" version_output)
	set(expected "HELIX ${HELIX_VERSION_STRING}")
	if(NOT version_output STREQUAL expected)
		message(FATAL_ERROR "helix ${flag} output '${version_output}', expected '${expected}'")
	endif()
endfunction()

function(run_step_case case_name step_env unset_env)
	set(run_dir "${HELIX_CLI_ROOT}/${case_name}")
	file(REMOVE_RECURSE "${run_dir}")
	file(MAKE_DIRECTORY "${run_dir}")

	execute_process(
		COMMAND "${CMAKE_COMMAND}" -E env "--unset=${unset_env}" "${step_env}=2" "${HELIX_EXECUTABLE}"
		WORKING_DIRECTORY "${run_dir}"
		RESULT_VARIABLE run_result
		OUTPUT_VARIABLE run_stdout
		ERROR_VARIABLE run_stderr
		TIMEOUT 300
	)
	if(NOT run_result EQUAL 0)
		message(FATAL_ERROR
			"helix compatibility run failed for ${step_env}=2\n"
			"stdout:\n${run_stdout}\n"
			"stderr:\n${run_stderr}"
		)
	endif()

	foreach(required_file IN ITEMS outputEnergy.txt output.txt output_rho0.txt snapshot_rho0.dat)
		if(NOT EXISTS "${run_dir}/${required_file}")
			message(FATAL_ERROR "${case_name} did not create ${required_file}")
		endif()
	endforeach()

	execute_process(
		COMMAND "${HELIX_ENERGY_COMPARE}" "${HELIX_REFERENCE_ENERGY}" "${run_dir}/outputEnergy.txt" "1e-5" "3"
		RESULT_VARIABLE compare_result
		OUTPUT_VARIABLE compare_stdout
		ERROR_VARIABLE compare_stderr
	)
	if(NOT compare_result EQUAL 0)
		message(FATAL_ERROR
			"outputEnergy comparison failed for ${case_name}\n"
			"stdout:\n${compare_stdout}\n"
			"stderr:\n${compare_stderr}"
		)
	endif()

	string(STRIP "${compare_stdout}" compare_summary)
	message(STATUS "${case_name}: ${compare_summary}")
endfunction()

assert_version("--version")
assert_version("-V")
run_step_case("helix-steps" "HELIX_STEPS" "HEOM_STEPS")
run_step_case("heom-steps-alias" "HEOM_STEPS" "HELIX_STEPS")
