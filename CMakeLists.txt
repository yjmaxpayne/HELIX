cmake_minimum_required(VERSION 3.24)

include(cmake/helix_version.cmake)

project(HELIX VERSION ${HELIX_VERSION} LANGUAGES CXX CUDA)

find_package(CUDAToolkit REQUIRED)
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

set(HELIX_GENERATED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(HELIX_CMAKE_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/HELIX")
file(MAKE_DIRECTORY "${HELIX_GENERATED_INCLUDE_DIR}/helix")
configure_file(
    cmake/helix_version_config.h.in
    "${HELIX_GENERATED_INCLUDE_DIR}/helix/version_config.h"
    @ONLY
)
message(STATUS "HELIX version: ${HELIX_VERSION_STRING} (${HELIX_VERSION_SOURCE})")

set(HELIX_CUDA_ARCHITECTURES "native" CACHE STRING "CUDA architectures for HELIX")
if(DEFINED HEOM_CUDA_ARCHITECTURES)
    set(HELIX_CUDA_ARCHITECTURES "${HEOM_CUDA_ARCHITECTURES}" CACHE STRING "CUDA architectures for HELIX" FORCE)
endif()

add_library(helix_host_core STATIC
    src/parameters.cu
    src/psd/eigenvalues.cu
    src/psd/psd.cu
)

target_include_directories(helix_host_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

set_target_properties(helix_host_core PROPERTIES
    CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
)

add_library(helix_core STATIC
    src/helix.cpp
    src/library/energy_observable.cpp
    src/library/legacy_runtime_session.cu
    src/library/result_extractor.cu
    src/parameters.cu
    src/psd/eigenvalues.cu
    src/psd/psd.cu
    src/initialize.cu
    src/liouville.cu
    src/matrix_storage.cu
    src/matrix_util.cu
)

add_library(HELIX::helix ALIAS helix_core)

target_include_directories(helix_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<BUILD_INTERFACE:${HELIX_GENERATED_INCLUDE_DIR}>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(helix_core PRIVATE
    CUDA::cublas
    CUDA::cusparse
)

set_target_properties(helix_core PROPERTIES
    OUTPUT_NAME helix
    EXPORT_NAME helix
    CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_RESOLVE_DEVICE_SYMBOLS ON
    POSITION_INDEPENDENT_CODE ON
)

add_executable(helix
    src/cli_compatibility.cu
    src/main.cu
)

target_include_directories(helix PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${HELIX_GENERATED_INCLUDE_DIR}
)

target_link_libraries(helix PRIVATE
    helix_core
    CUDA::cublas
    CUDA::cusparse
)

set_target_properties(helix PROPERTIES
    CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_RESOLVE_DEVICE_SYMBOLS ON
)

install(TARGETS helix_core
    EXPORT HELIXTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(TARGETS helix
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(FILES "${HELIX_GENERATED_INCLUDE_DIR}/helix/version_config.h"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/helix
)

install(EXPORT HELIXTargets
    FILE HELIXTargets.cmake
    NAMESPACE HELIX::
    DESTINATION ${HELIX_CMAKE_INSTALL_DIR}
)

configure_package_config_file(
    cmake/HELIXConfig.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/HELIXConfig.cmake"
    INSTALL_DESTINATION ${HELIX_CMAKE_INSTALL_DIR}
)

write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/HELIXConfigVersion.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)

export(EXPORT HELIXTargets
    FILE "${CMAKE_CURRENT_BINARY_DIR}/HELIXTargets.cmake"
    NAMESPACE HELIX::
)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/HELIXConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/HELIXConfigVersion.cmake"
    DESTINATION ${HELIX_CMAKE_INSTALL_DIR}
)

option(HELIX_BUILD_PYTHON "Build the experimental HELIX Python binding" OFF)
option(HELIX_BUILD_TESTS "Build HELIX test executables" ON)

if(HELIX_BUILD_PYTHON)
    find_package(Python3 REQUIRED COMPONENTS Interpreter Development.Module)

    if(NOT pybind11_DIR)
        execute_process(
            COMMAND "${Python3_EXECUTABLE}" -m pybind11 --cmakedir
            RESULT_VARIABLE HELIX_PYBIND11_CMAKEDIR_RESULT
            OUTPUT_VARIABLE HELIX_PYBIND11_CMAKEDIR
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )

        if(HELIX_PYBIND11_CMAKEDIR_RESULT EQUAL 0
            AND EXISTS "${HELIX_PYBIND11_CMAKEDIR}/pybind11Config.cmake")
            set(pybind11_DIR "${HELIX_PYBIND11_CMAKEDIR}" CACHE PATH "pybind11 CMake package directory")
        endif()
    endif()

    find_package(pybind11 CONFIG QUIET)
    if(NOT pybind11_FOUND)
        message(FATAL_ERROR
            "HELIX_BUILD_PYTHON=ON requires pybind11 in the selected Python environment. "
            "Install project Python dependencies in a virtual environment, for example "
            "`uv venv --python 3.13 .venv && uv pip install -e \".[dev]\"`. Reconfigure with "
            "-DPython3_EXECUTABLE=<venv>/bin/python, or pass "
            "-Dpybind11_DIR=$(python -m pybind11 --cmakedir).")
    endif()

    pybind11_add_module(helix_python MODULE
        bindings/python/helix_bindings.cpp
    )

    target_link_libraries(helix_python PRIVATE
        helix_core
        CUDA::cublas
        CUDA::cusparse
    )

    set_target_properties(helix_python PROPERTIES
        OUTPUT_NAME helix
    )
endif()

if(HELIX_BUILD_TESTS)
    enable_testing()

    add_library(helix_test_support INTERFACE)

    target_include_directories(helix_test_support INTERFACE
        ${CMAKE_CURRENT_SOURCE_DIR}/tests
    )

    find_program(HELIX_COMPUTE_SANITIZER compute-sanitizer
        HINTS "${CUDAToolkit_BIN_DIR}"
        DOC "Path to NVIDIA compute-sanitizer"
    )
    set(HELIX_COMPUTE_SANITIZER_DEFINITION "")
    if(HELIX_COMPUTE_SANITIZER)
        set(HELIX_COMPUTE_SANITIZER_DEFINITION "-DHELIX_COMPUTE_SANITIZER=${HELIX_COMPUTE_SANITIZER}")
    endif()

    # CTest label contract shared by the test-suite refactor tasks.
    set(HELIX_KNOWN_TEST_LABELS
        unit
        cuda
        numerical
        integration
        baseline
        sanitizer
        benchmark
    )

    function(helix_require_known_test_labels)
        foreach(label IN LISTS ARGN)
            list(FIND HELIX_KNOWN_TEST_LABELS "${label}" label_index)
            if(label_index EQUAL -1)
                message(FATAL_ERROR "Unknown HELIX test label: ${label}")
            endif()
        endforeach()
    endfunction()

    function(helix_add_test)
        set(options GPU EXPECTED_FAIL)
        set(one_value_args NAME TARGET TIMEOUT)
        set(multi_value_args LABELS COMMAND)
        cmake_parse_arguments(HELIX_TEST "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

        if(NOT HELIX_TEST_NAME)
            message(FATAL_ERROR "helix_add_test requires NAME")
        endif()
        if(NOT HELIX_TEST_LABELS)
            message(FATAL_ERROR "helix_add_test requires at least one LABELS entry")
        endif()
        if(NOT HELIX_TEST_TIMEOUT)
            set(HELIX_TEST_TIMEOUT 30)
        endif()

        set(test_command ${HELIX_TEST_COMMAND})
        if(NOT test_command)
            if(NOT HELIX_TEST_TARGET)
                message(FATAL_ERROR "helix_add_test requires TARGET or COMMAND")
            endif()
            set(test_command ${HELIX_TEST_TARGET})
        endif()

        set(test_labels ${HELIX_TEST_LABELS})
        if(HELIX_TEST_GPU)
            list(FIND test_labels sanitizer sanitizer_label_index)
            list(FIND test_labels benchmark benchmark_label_index)
            list(FIND test_labels unit unit_label_index)
            if(NOT unit_label_index EQUAL -1)
                message(FATAL_ERROR "GPU tests must not use the unit label")
            endif()

            if(sanitizer_label_index EQUAL -1 AND benchmark_label_index EQUAL -1)
                list(FIND test_labels cuda cuda_label_index)
                if(cuda_label_index EQUAL -1)
                    list(APPEND test_labels cuda)
                endif()
            endif()
        endif()

        helix_require_known_test_labels(${test_labels})

        add_test(NAME "${HELIX_TEST_NAME}" COMMAND ${test_command})

        set_tests_properties("${HELIX_TEST_NAME}" PROPERTIES
            LABELS "${test_labels}"
            TIMEOUT "${HELIX_TEST_TIMEOUT}"
        )

        if(HELIX_TEST_EXPECTED_FAIL)
            set_tests_properties("${HELIX_TEST_NAME}" PROPERTIES
                WILL_FAIL TRUE
            )
        endif()

        if(HELIX_TEST_GPU)
            set_tests_properties("${HELIX_TEST_NAME}" PROPERTIES
                RESOURCE_LOCK gpu
            )
        endif()
    endfunction()

    set(HELIX_V01_EXPECTED_FAIL_SCRIPT
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/planned/expected_fail_gate.cmake
    )

    function(helix_add_v01_expected_fail_gate)
        set(options GPU)
        set(one_value_args NAME TASK REASON TIMEOUT)
        set(multi_value_args LABELS)
        cmake_parse_arguments(HELIX_V01_GATE "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

        if(NOT HELIX_V01_GATE_NAME)
            message(FATAL_ERROR "helix_add_v01_expected_fail_gate requires NAME")
        endif()
        if(NOT HELIX_V01_GATE_TASK)
            message(FATAL_ERROR "helix_add_v01_expected_fail_gate requires TASK")
        endif()
        if(NOT HELIX_V01_GATE_REASON)
            message(FATAL_ERROR "helix_add_v01_expected_fail_gate requires REASON")
        endif()
        if(NOT HELIX_V01_GATE_TIMEOUT)
            set(HELIX_V01_GATE_TIMEOUT 10)
        endif()

        set(gpu_arg)
        if(HELIX_V01_GATE_GPU)
            set(gpu_arg GPU)
        endif()

        helix_add_test(
            NAME ${HELIX_V01_GATE_NAME}
            COMMAND
                ${CMAKE_COMMAND}
                "-DHELIX_GATE_NAME=${HELIX_V01_GATE_NAME}"
                "-DHELIX_GATE_TASK=${HELIX_V01_GATE_TASK}"
                "-DHELIX_GATE_REASON=${HELIX_V01_GATE_REASON}"
                -P ${HELIX_V01_EXPECTED_FAIL_SCRIPT}
            LABELS ${HELIX_V01_GATE_LABELS}
            TIMEOUT ${HELIX_V01_GATE_TIMEOUT}
            EXPECTED_FAIL
            ${gpu_arg}
        )
    endfunction()

    # v0.1 library foundation gates remain expected failures until each
    # downstream task replaces the placeholder with the real test.
    add_executable(v01_public_header_compile_gate
        tests/unit/public_header_compile_tests.cpp
    )

    target_link_libraries(v01_public_header_compile_gate PRIVATE
        helix_core
    )

    helix_add_test(
        NAME v01_public_header_compile_gate
        TARGET v01_public_header_compile_gate
        LABELS unit
        TIMEOUT 10
    )

    helix_add_test(
        NAME v01_external_consumer_cmake_gate
        COMMAND
            ${CMAKE_COMMAND}
            -DHELIX_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
            -DHELIX_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
            -DHELIX_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/external-consumer-smoke
            -DHELIX_CUDA_ARCHITECTURES=${HELIX_CUDA_ARCHITECTURES}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/external_consumer_smoke.cmake
        LABELS integration
        TIMEOUT 120
    )

    add_executable(api_schema_validation_tests
        tests/unit/api_schema_validation_tests.cpp
    )

    target_link_libraries(api_schema_validation_tests PRIVATE
        helix_core
        helix_test_support
    )

    helix_add_test(
        NAME v01_api_schema_validation_gate
        TARGET api_schema_validation_tests
        LABELS unit
        TIMEOUT 10
    )

    add_executable(benchmark_schema_validation_tests
        tests/unit/benchmark_schema_validation_tests.cpp
    )

    target_link_libraries(benchmark_schema_validation_tests PRIVATE
        helix_core
        helix_test_support
    )

    helix_add_test(
        NAME benchmark_schema_validation_tests
        TARGET benchmark_schema_validation_tests
        LABELS unit
        TIMEOUT 10
    )

    add_executable(benchmark_artifact_hygiene_tests
        tests/unit/benchmark_artifact_hygiene_tests.cpp
    )

    target_link_libraries(benchmark_artifact_hygiene_tests PRIVATE
        helix_test_support
    )

    helix_add_test(
        NAME benchmark_artifact_hygiene_tests
        TARGET benchmark_artifact_hygiene_tests
        LABELS unit
        TIMEOUT 10
    )

    set(HELIX_BENCHMARK_BUILD_TYPE "${CMAKE_BUILD_TYPE}")
    if(NOT HELIX_BENCHMARK_BUILD_TYPE)
        set(HELIX_BENCHMARK_BUILD_TYPE "unknown")
    endif()

    add_executable(legacy_spin_glass_benchmark
        tests/benchmark/legacy_spin_glass_benchmark.cu
    )

    target_link_libraries(legacy_spin_glass_benchmark PRIVATE
        helix_core
        helix_test_support
        CUDA::cudart
    )

    target_compile_definitions(legacy_spin_glass_benchmark PRIVATE
        HELIX_BENCHMARK_BUILD_TYPE="${HELIX_BENCHMARK_BUILD_TYPE}"
        HELIX_BENCHMARK_CUDA_ARCHITECTURES="${HELIX_CUDA_ARCHITECTURES}"
        HELIX_BENCHMARK_COMPILER="${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}"
        HELIX_BENCHMARK_DEFAULT_OUTPUT_DIR="${CMAKE_CURRENT_BINARY_DIR}/benchmark"
    )

    set_target_properties(legacy_spin_glass_benchmark PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME v003_legacy_spin_glass_benchmark_gate
        TARGET legacy_spin_glass_benchmark
        LABELS benchmark
        GPU
        TIMEOUT 180
    )

    helix_add_test(
        NAME v003_ctest_label_resource_lock_review
        COMMAND
            ${CMAKE_COMMAND}
            -DHELIX_CTEST_COMMAND=${CMAKE_CTEST_COMMAND}
            -DHELIX_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
            -DHELIX_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
            -DHELIX_BENCHMARK_TEST_NAME=v003_legacy_spin_glass_benchmark_gate
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/ctest_label_resource_lock_review.cmake
        LABELS integration
        TIMEOUT 30
    )

    add_executable(public_lifecycle_context_tests
        tests/numerical/public_lifecycle_context_tests.cu
    )

    target_link_libraries(public_lifecycle_context_tests PRIVATE
        helix_core
        helix_test_support
    )

    target_include_directories(public_lifecycle_context_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(public_lifecycle_context_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME v01_public_lifecycle_numerical_gate
        TARGET public_lifecycle_context_tests
        LABELS numerical
        GPU
        TIMEOUT 180
    )

    add_executable(public_solver_spin_glass_tests
        tests/numerical/public_solver_spin_glass_tests.cu
    )

    target_link_libraries(public_solver_spin_glass_tests PRIVATE
        helix_core
        helix_test_support
    )

    target_include_directories(public_solver_spin_glass_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(public_solver_spin_glass_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME v01_public_solver_spin_glass_gate
        TARGET public_solver_spin_glass_tests
        LABELS numerical
        GPU
        TIMEOUT 180
    )

    add_executable(public_result_shape_tests
        tests/numerical/public_result_shape_tests.cu
    )

    target_link_libraries(public_result_shape_tests PRIVATE
        helix_core
        helix_test_support
    )

    target_include_directories(public_result_shape_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(public_result_shape_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME v01_result_shape_no_file_output_gate
        TARGET public_result_shape_tests
        LABELS numerical integration
        GPU
        TIMEOUT 180
    )

    add_executable(cli_compatibility_tests
        tests/unit/cli_compatibility_tests.cpp
    )

    target_link_libraries(cli_compatibility_tests PRIVATE
        helix_test_support
    )

    target_include_directories(cli_compatibility_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    helix_add_test(
        NAME cli_compatibility_tests
        TARGET cli_compatibility_tests
        LABELS unit
        TIMEOUT 10
    )

    add_executable(energy_observable_tests
        tests/unit/energy_observable_tests.cpp
        src/library/energy_observable.cpp
    )

    target_link_libraries(energy_observable_tests PRIVATE
        helix_test_support
    )

    target_include_directories(energy_observable_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    helix_add_test(
        NAME energy_observable_tests
        TARGET energy_observable_tests
        LABELS unit
        TIMEOUT 10
    )

    helix_add_test(
        NAME v01_cli_compatibility_wrapper_gate
        COMMAND
            ${CMAKE_COMMAND}
            -DHELIX_EXECUTABLE=$<TARGET_FILE:helix>
            -DHELIX_VERSION_STRING=${HELIX_VERSION_STRING}
            -DHELIX_ENERGY_COMPARE=$<TARGET_FILE:energy_trace_compare>
            -DHELIX_REFERENCE_ENERGY=${CMAKE_CURRENT_SOURCE_DIR}/examples/outputEnergy.txt
            -DHELIX_CLI_ROOT=${CMAKE_CURRENT_BINARY_DIR}/cli-compatibility-wrapper
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/cli_compatibility_wrapper.cmake
        LABELS integration baseline
        GPU
        TIMEOUT 300
    )

    if(HELIX_BUILD_PYTHON)
        helix_add_test(
            NAME v01_python_smoke_gate
            COMMAND
                ${CMAKE_COMMAND}
                -DHELIX_PYTHON_EXECUTABLE=${Python3_EXECUTABLE}
                -DHELIX_PYTHON_MODULE_DIR=$<TARGET_FILE_DIR:helix_python>
                -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/python_binding_smoke.cmake
            LABELS integration
            GPU
            TIMEOUT 300
        )
    endif()

    add_executable(v01_cpp_library_example
        examples/cpp/legacy_spin_glass.cpp
    )

    target_link_libraries(v01_cpp_library_example PRIVATE
        helix_core
    )

    helix_add_test(
        NAME v01_cpp_library_example_gate
        TARGET v01_cpp_library_example
        LABELS integration
        GPU
        TIMEOUT 180
    )

    add_executable(initialize_detail_tests
        tests/unit/initialize_detail_tests.cu
    )

    target_link_libraries(initialize_detail_tests PRIVATE
        helix_host_core
        helix_test_support
    )

    set_target_properties(initialize_detail_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    )

    helix_add_test(
        NAME initialize_detail_tests
        TARGET initialize_detail_tests
        LABELS unit
        TIMEOUT 10
    )

    add_executable(psd_reference_tests
        tests/unit/psd_reference_tests.cu
    )

    target_link_libraries(psd_reference_tests PRIVATE
        helix_host_core
        helix_test_support
    )

    set_target_properties(psd_reference_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    )

    helix_add_test(
        NAME psd_reference_tests
        TARGET psd_reference_tests
        LABELS unit
        TIMEOUT 10
    )

    add_executable(parameter_default_tests
        tests/unit/parameter_default_tests.cu
    )

    target_link_libraries(parameter_default_tests PRIVATE
        helix_host_core
        helix_test_support
    )

    set_target_properties(parameter_default_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    )

    helix_add_test(
        NAME parameter_default_tests
        TARGET parameter_default_tests
        LABELS unit
        TIMEOUT 10
    )

    add_executable(energy_trace_comparator_tests
        tests/unit/energy_trace_comparator_tests.cpp
    )

    target_link_libraries(energy_trace_comparator_tests PRIVATE
        helix_test_support
    )

    target_compile_definitions(energy_trace_comparator_tests PRIVATE
        HELIX_EXAMPLE_ENERGY_PATH="${CMAKE_CURRENT_SOURCE_DIR}/examples/outputEnergy.txt"
    )

    helix_add_test(
        NAME energy_trace_comparator_tests
        TARGET energy_trace_comparator_tests
        LABELS unit baseline
        TIMEOUT 10
    )

    add_executable(transpose_cuda_tests
        tests/cuda/transpose_tests.cu
        src/matrix_util.cu
    )

    target_link_libraries(transpose_cuda_tests PRIVATE
        helix_test_support
        CUDA::cublas
    )

    target_include_directories(transpose_cuda_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(transpose_cuda_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    )

    helix_add_test(
        NAME transpose_cuda_tests
        TARGET transpose_cuda_tests
        LABELS cuda
        GPU
        TIMEOUT 60
    )

    helix_add_test(
        NAME helix_cuda_memcheck_sanitizer
        COMMAND
            ${CMAKE_COMMAND}
            -DHELIX_SANITIZER_TEST_NAME=helix_cuda_memcheck_sanitizer
            -DHELIX_SANITIZER_TARGET=$<TARGET_FILE:transpose_cuda_tests>
            -DHELIX_SANITIZER_REPORT_DIR=${CMAKE_CURRENT_BINARY_DIR}/sanitizer
            -DHELIX_SANITIZER_TOOL=memcheck
            ${HELIX_COMPUTE_SANITIZER_DEFINITION}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/sanitizer/run_cuda_sanitizer.cmake
        LABELS sanitizer
        GPU
        TIMEOUT 600
    )

    add_executable(cusparse_wrapper_cuda_tests
        tests/cuda/cusparse_wrapper_tests.cu
    )

    target_link_libraries(cusparse_wrapper_cuda_tests PRIVATE
        helix_test_support
        CUDA::cusparse
    )

    target_include_directories(cusparse_wrapper_cuda_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(cusparse_wrapper_cuda_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    )

    helix_add_test(
        NAME cusparse_wrapper_cuda_tests
        TARGET cusparse_wrapper_cuda_tests
        LABELS cuda
        GPU
        TIMEOUT 60
    )

    add_executable(sparse_drho_reference_tests
        tests/numerical/sparse_drho_reference_tests.cu
        src/initialize.cu
        src/liouville.cu
        src/matrix_storage.cu
        src/matrix_util.cu
    )

    target_link_libraries(sparse_drho_reference_tests PRIVATE
        helix_host_core
        helix_test_support
        CUDA::cublas
        CUDA::cusparse
    )

    target_include_directories(sparse_drho_reference_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(sparse_drho_reference_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME sparse_drho_reference_tests
        TARGET sparse_drho_reference_tests
        LABELS numerical
        GPU
        TIMEOUT 180
    )

    add_executable(one_step_evolution_tests
        tests/numerical/one_step_evolution_tests.cu
        src/initialize.cu
        src/liouville.cu
        src/matrix_storage.cu
        src/matrix_util.cu
    )

    target_link_libraries(one_step_evolution_tests PRIVATE
        helix_host_core
        helix_test_support
        CUDA::cublas
        CUDA::cusparse
    )

    target_include_directories(one_step_evolution_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(one_step_evolution_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME one_step_evolution_tests
        TARGET one_step_evolution_tests
        LABELS numerical
        GPU
        TIMEOUT 180
    )

    add_executable(heom_lifecycle_contract_tests
        tests/numerical/heom_lifecycle_contract_tests.cu
        src/initialize.cu
        src/liouville.cu
        src/matrix_storage.cu
        src/matrix_util.cu
    )

    target_link_libraries(heom_lifecycle_contract_tests PRIVATE
        helix_host_core
        helix_test_support
        CUDA::cublas
        CUDA::cusparse
    )

    target_include_directories(heom_lifecycle_contract_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    set_target_properties(heom_lifecycle_contract_tests PROPERTIES
        CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_RESOLVE_DEVICE_SYMBOLS ON
    )

    helix_add_test(
        NAME heom_lifecycle_contract_tests
        TARGET heom_lifecycle_contract_tests
        LABELS numerical
        GPU
        TIMEOUT 180
    )

    add_executable(energy_trace_compare
        tests/support/energy_trace_compare_main.cpp
    )

    target_link_libraries(energy_trace_compare PRIVATE
        helix_test_support
    )

    helix_add_test(
        NAME helix_smoke_integration
        COMMAND
            ${CMAKE_COMMAND}
            -DHELIX_EXECUTABLE=$<TARGET_FILE:helix>
            -DHELIX_ENERGY_COMPARE=$<TARGET_FILE:energy_trace_compare>
            -DHELIX_REFERENCE_ENERGY=${CMAKE_CURRENT_SOURCE_DIR}/examples/outputEnergy.txt
            -DHELIX_SMOKE_ROOT=${CMAKE_CURRENT_BINARY_DIR}/helix-smoke-integration
            -DHELIX_ENERGY_TOLERANCE=1e-5
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/helix_smoke_integration.cmake
        LABELS integration baseline
        GPU
        TIMEOUT 300
    )
endif()
