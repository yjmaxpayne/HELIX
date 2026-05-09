cmake_minimum_required(VERSION 3.24)

include(cmake/HelixVersion.cmake)

project(HELIX VERSION ${HELIX_VERSION} LANGUAGES CXX CUDA)

find_package(CUDAToolkit REQUIRED)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

set(HELIX_GENERATED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
configure_file(
    src/HelixVersion.h.in
    "${HELIX_GENERATED_INCLUDE_DIR}/HelixVersion.h"
    @ONLY
)
message(STATUS "HELIX version: ${HELIX_VERSION_STRING} (${HELIX_VERSION_SOURCE})")

set(HELIX_CUDA_ARCHITECTURES "native" CACHE STRING "CUDA architectures for HELIX")
if(DEFINED HEOM_CUDA_ARCHITECTURES)
    set(HELIX_CUDA_ARCHITECTURES "${HEOM_CUDA_ARCHITECTURES}" CACHE STRING "CUDA architectures for HELIX" FORCE)
endif()

add_library(helix_host_core STATIC
    src/Parameters.cu
    src/Psd/Eigval.cu
    src/Psd/Psd.cu
)

target_include_directories(helix_host_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

set_target_properties(helix_host_core PROPERTIES
    CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
)

add_executable(helix
    src/Main.cu
    src/Initialize.cu
    src/Liouville.cu
    src/Matrixes.cu
    src/MatrixUtil.cu
)

target_include_directories(helix PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${HELIX_GENERATED_INCLUDE_DIR}
)

target_link_libraries(helix PRIVATE
    helix_host_core
    CUDA::cublas
    CUDA::cusparse
)

set_target_properties(helix PROPERTIES
    CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_RESOLVE_DEVICE_SYMBOLS ON
)

option(HELIX_BUILD_TESTS "Build HELIX test executables" ON)

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
        set(options GPU)
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
            list(FIND test_labels unit unit_label_index)
            if(NOT unit_label_index EQUAL -1)
                message(FATAL_ERROR "GPU tests must not use the unit label")
            endif()

            if(sanitizer_label_index EQUAL -1)
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

        if(HELIX_TEST_GPU)
            set_tests_properties("${HELIX_TEST_NAME}" PROPERTIES
                RESOURCE_LOCK gpu
            )
        endif()
    endfunction()

    add_executable(initialize_detail_tests
        tests/unit/InitializeDetailTests.cu
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
        tests/unit/PsdReferenceTests.cu
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
        tests/unit/ParameterDefaultTests.cu
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
        tests/unit/EnergyTraceComparatorTests.cpp
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
        tests/cuda/TransposeTests.cu
        src/MatrixUtil.cu
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
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/sanitizer/RunCudaSanitizer.cmake
        LABELS sanitizer
        GPU
        TIMEOUT 600
    )

    add_executable(cusparse_wrapper_cuda_tests
        tests/cuda/CusparseWrapperTests.cu
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
        tests/numerical/SparseDrhoReferenceTests.cu
        src/Initialize.cu
        src/Liouville.cu
        src/Matrixes.cu
        src/MatrixUtil.cu
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
        tests/numerical/OneStepEvolutionTests.cu
        src/Initialize.cu
        src/Liouville.cu
        src/Matrixes.cu
        src/MatrixUtil.cu
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
        tests/numerical/HeomLifecycleContractTests.cu
        src/Initialize.cu
        src/Liouville.cu
        src/Matrixes.cu
        src/MatrixUtil.cu
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
        tests/support/EnergyTraceCompareMain.cpp
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
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/HelixSmokeIntegration.cmake
        LABELS integration baseline
        GPU
        TIMEOUT 300
    )
endif()
