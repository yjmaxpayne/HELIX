cmake_minimum_required(VERSION 3.24)

foreach(required_var IN ITEMS HELIX_SOURCE_DIR HELIX_BINARY_DIR HELIX_TEST_ROOT HELIX_CUDA_ARCHITECTURES)
    if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
        message(FATAL_ERROR "External consumer smoke requires ${required_var}")
    endif()
endforeach()

file(REMOVE_RECURSE "${HELIX_TEST_ROOT}")
file(MAKE_DIRECTORY "${HELIX_TEST_ROOT}")

set(consumer_source_dir "${HELIX_TEST_ROOT}/consumer-src")
file(MAKE_DIRECTORY "${consumer_source_dir}")

file(WRITE "${consumer_source_dir}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.24)
project(HELIXConsumerSmoke LANGUAGES CXX CUDA)

find_package(HELIX CONFIG REQUIRED)

add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE HELIX::helix)
]=])

file(WRITE "${consumer_source_dir}/main.cpp" [=[
#include <helix/helix.h>

#include <cstring>
#include <iostream>

int main()
{
	if(helix::versionString()[0] == '\0')
	{
		return 1;
	}
	if(std::strcmp(helix::versionString(), helix::runtimeVersion()) != 0)
	{
		return 2;
	}
	std::cout << "consumer linked HELIX " << helix::versionString() << "\n";
	return 0;
}
]=])

function(run_consumer_smoke case_name package_prefix)
    set(consumer_binary_dir "${HELIX_TEST_ROOT}/${case_name}-build")

    execute_process(
        COMMAND
            "${CMAKE_COMMAND}"
            -S "${consumer_source_dir}"
            -B "${consumer_binary_dir}"
            "-DCMAKE_BUILD_TYPE=Release"
            "-DCMAKE_PREFIX_PATH=${package_prefix}"
            "-DCMAKE_CUDA_ARCHITECTURES=${HELIX_CUDA_ARCHITECTURES}"
        RESULT_VARIABLE configure_result
        OUTPUT_VARIABLE configure_output
        ERROR_VARIABLE configure_error
    )
    if(NOT configure_result EQUAL 0)
        message(FATAL_ERROR
            "Failed to configure ${case_name} consumer\n"
            "stdout:\n${configure_output}\n"
            "stderr:\n${configure_error}"
        )
    endif()

    execute_process(
        COMMAND "${CMAKE_COMMAND}" --build "${consumer_binary_dir}"
        RESULT_VARIABLE build_result
        OUTPUT_VARIABLE build_output
        ERROR_VARIABLE build_error
    )
    if(NOT build_result EQUAL 0)
        message(FATAL_ERROR
            "Failed to build ${case_name} consumer\n"
            "stdout:\n${build_output}\n"
            "stderr:\n${build_error}"
        )
    endif()

    execute_process(
        COMMAND "${consumer_binary_dir}/consumer"
        RESULT_VARIABLE run_result
        OUTPUT_VARIABLE run_output
        ERROR_VARIABLE run_error
    )
    if(NOT run_result EQUAL 0)
        message(FATAL_ERROR
            "Failed to run ${case_name} consumer\n"
            "stdout:\n${run_output}\n"
            "stderr:\n${run_error}"
        )
    endif()

    message(STATUS "${case_name} consumer output: ${run_output}")
endfunction()

run_consumer_smoke("build-tree" "${HELIX_BINARY_DIR}")

set(install_prefix "${HELIX_TEST_ROOT}/install")
execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${HELIX_BINARY_DIR}" --prefix "${install_prefix}"
    RESULT_VARIABLE install_result
    OUTPUT_VARIABLE install_output
    ERROR_VARIABLE install_error
)
if(NOT install_result EQUAL 0)
    message(FATAL_ERROR
        "Failed to install HELIX for consumer smoke\n"
        "stdout:\n${install_output}\n"
        "stderr:\n${install_error}"
    )
endif()

run_consumer_smoke("install-tree" "${install_prefix}")
