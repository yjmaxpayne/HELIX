if(NOT DEFINED HELIX_EXECUTABLE)
	message(FATAL_ERROR "HELIX_EXECUTABLE is required")
endif()
if(NOT DEFINED HELIX_ENERGY_COMPARE)
	message(FATAL_ERROR "HELIX_ENERGY_COMPARE is required")
endif()
if(NOT DEFINED HELIX_REFERENCE_ENERGY)
	message(FATAL_ERROR "HELIX_REFERENCE_ENERGY is required")
endif()
if(NOT DEFINED HELIX_SMOKE_ROOT)
	message(FATAL_ERROR "HELIX_SMOKE_ROOT is required")
endif()
if(NOT DEFINED HELIX_ENERGY_TOLERANCE)
	set(HELIX_ENERGY_TOLERANCE "1e-5")
endif()

file(MAKE_DIRECTORY "${HELIX_SMOKE_ROOT}")

foreach(step IN ITEMS 0 1 2)
	math(EXPR expected_rows "${step} + 1")
	set(run_dir "${HELIX_SMOKE_ROOT}/steps-${step}")
	file(REMOVE_RECURSE "${run_dir}")
	file(MAKE_DIRECTORY "${run_dir}")

	execute_process(
		COMMAND "${CMAKE_COMMAND}" -E env "HELIX_STEPS=${step}" "${HELIX_EXECUTABLE}"
		WORKING_DIRECTORY "${run_dir}"
		RESULT_VARIABLE helix_result
		OUTPUT_VARIABLE helix_stdout
		ERROR_VARIABLE helix_stderr
		TIMEOUT 300
	)
	if(NOT helix_result EQUAL 0)
		message(FATAL_ERROR
			"helix smoke failed for HELIX_STEPS=${step}\n"
			"stdout:\n${helix_stdout}\n"
			"stderr:\n${helix_stderr}"
		)
	endif()

	set(actual_energy "${run_dir}/outputEnergy.txt")
	if(NOT EXISTS "${actual_energy}")
		message(FATAL_ERROR "helix smoke did not create ${actual_energy}")
	endif()

	execute_process(
		COMMAND "${HELIX_ENERGY_COMPARE}" "${HELIX_REFERENCE_ENERGY}" "${actual_energy}" "${HELIX_ENERGY_TOLERANCE}" "${expected_rows}"
		RESULT_VARIABLE compare_result
		OUTPUT_VARIABLE compare_stdout
		ERROR_VARIABLE compare_stderr
	)
	if(NOT compare_result EQUAL 0)
		message(FATAL_ERROR
			"outputEnergy comparison failed for HELIX_STEPS=${step}\n"
			"stdout:\n${compare_stdout}\n"
			"stderr:\n${compare_stderr}"
		)
	endif()

	message(STATUS "HELIX_STEPS=${step}: ${compare_stdout}")
endforeach()
