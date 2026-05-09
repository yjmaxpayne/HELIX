if(NOT DEFINED HELIX_SANITIZER_TEST_NAME)
	message(FATAL_ERROR "HELIX_SANITIZER_TEST_NAME is required")
endif()
if(NOT DEFINED HELIX_SANITIZER_TARGET)
	message(FATAL_ERROR "HELIX_SANITIZER_TARGET is required")
endif()
if(NOT DEFINED HELIX_SANITIZER_TOOL)
	set(HELIX_SANITIZER_TOOL "memcheck")
endif()

if(NOT EXISTS "${HELIX_SANITIZER_TARGET}")
	message(FATAL_ERROR "Sanitizer target does not exist: ${HELIX_SANITIZER_TARGET}")
endif()

set(report_root "$ENV{HELIX_SANITIZER_REPORT_DIR}")
if("${report_root}" STREQUAL "" AND DEFINED HELIX_SANITIZER_REPORT_DIR)
	set(report_root "${HELIX_SANITIZER_REPORT_DIR}")
endif()
if("${report_root}" STREQUAL "")
	set(report_root "${CMAKE_CURRENT_BINARY_DIR}/sanitizer")
endif()

file(MAKE_DIRECTORY "${report_root}")

set(report_path "${report_root}/${HELIX_SANITIZER_TEST_NAME}-${HELIX_SANITIZER_TOOL}.log")
set(stdout_path "${report_root}/${HELIX_SANITIZER_TEST_NAME}-stdout.txt")
set(stderr_path "${report_root}/${HELIX_SANITIZER_TEST_NAME}-stderr.txt")
set(summary_path "${report_root}/${HELIX_SANITIZER_TEST_NAME}-summary.txt")

set(compute_sanitizer "$ENV{HELIX_COMPUTE_SANITIZER}")
if("${compute_sanitizer}" STREQUAL "" AND DEFINED HELIX_COMPUTE_SANITIZER)
	set(compute_sanitizer "${HELIX_COMPUTE_SANITIZER}")
endif()
if("${compute_sanitizer}" STREQUAL "")
	find_program(compute_sanitizer compute-sanitizer)
endif()
if("${compute_sanitizer}" STREQUAL "compute_sanitizer-NOTFOUND" OR "${compute_sanitizer}" STREQUAL "")
	message(FATAL_ERROR "compute-sanitizer was not found; set HELIX_COMPUTE_SANITIZER to override")
endif()

message(STATUS "Running ${compute_sanitizer} --tool ${HELIX_SANITIZER_TOOL} for ${HELIX_SANITIZER_TARGET}")
message(STATUS "Sanitizer report: ${report_path}")

execute_process(
	COMMAND
		"${compute_sanitizer}"
		--tool "${HELIX_SANITIZER_TOOL}"
		--error-exitcode 86
		--log-file "${report_path}"
		"${HELIX_SANITIZER_TARGET}"
	RESULT_VARIABLE sanitizer_result
	OUTPUT_VARIABLE sanitizer_stdout
	ERROR_VARIABLE sanitizer_stderr
	TIMEOUT 540
)

file(WRITE "${stdout_path}" "${sanitizer_stdout}")
file(WRITE "${stderr_path}" "${sanitizer_stderr}")
file(WRITE "${summary_path}"
	"test=${HELIX_SANITIZER_TEST_NAME}\n"
	"tool=${HELIX_SANITIZER_TOOL}\n"
	"target=${HELIX_SANITIZER_TARGET}\n"
	"report=${report_path}\n"
	"stdout=${stdout_path}\n"
	"stderr=${stderr_path}\n"
	"result=${sanitizer_result}\n"
)

if(NOT sanitizer_result EQUAL 0)
	message(FATAL_ERROR
		"compute-sanitizer failed with exit code ${sanitizer_result}\n"
		"report: ${report_path}\n"
		"stdout:\n${sanitizer_stdout}\n"
		"stderr:\n${sanitizer_stderr}"
	)
endif()

message(STATUS "compute-sanitizer completed successfully")
