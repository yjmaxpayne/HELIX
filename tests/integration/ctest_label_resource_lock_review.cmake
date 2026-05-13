if(NOT DEFINED HELIX_CTEST_COMMAND)
    message(FATAL_ERROR "HELIX_CTEST_COMMAND is required")
endif()
if(NOT DEFINED HELIX_BINARY_DIR)
    message(FATAL_ERROR "HELIX_BINARY_DIR is required")
endif()
if(NOT DEFINED HELIX_SOURCE_DIR)
    message(FATAL_ERROR "HELIX_SOURCE_DIR is required")
endif()
if(NOT DEFINED HELIX_BENCHMARK_TEST_NAME)
    message(FATAL_ERROR "HELIX_BENCHMARK_TEST_NAME is required")
endif()

execute_process(
    COMMAND
        "${HELIX_CTEST_COMMAND}"
        --test-dir "${HELIX_BINARY_DIR}"
        --show-only=json-v1
    RESULT_VARIABLE ctest_result
    OUTPUT_VARIABLE HELIX_CTEST_JSON
    ERROR_VARIABLE ctest_error
)

if(NOT ctest_result EQUAL 0)
    message(FATAL_ERROR "ctest property query failed: ${ctest_error}")
endif()

function(helix_find_test_index test_name out_var)
    string(JSON test_count LENGTH "${HELIX_CTEST_JSON}" tests)
    if(test_count EQUAL 0)
        message(FATAL_ERROR "CTest JSON contains no tests")
    endif()

    math(EXPR last_test_index "${test_count} - 1")
    set(found_index -1)
    foreach(test_index RANGE 0 ${last_test_index})
        string(JSON current_name GET "${HELIX_CTEST_JSON}" tests ${test_index} name)
        if(current_name STREQUAL test_name)
            set(found_index ${test_index})
        endif()
    endforeach()

    if(found_index EQUAL -1)
        message(FATAL_ERROR "CTest test not found: ${test_name}")
    endif()

    set(${out_var} "${found_index}" PARENT_SCOPE)
endfunction()

function(helix_get_test_property test_index property_name out_var)
    set(found FALSE)
    set(values)
    string(JSON property_count LENGTH "${HELIX_CTEST_JSON}" tests ${test_index} properties)

    if(property_count GREATER 0)
        math(EXPR last_property_index "${property_count} - 1")
        foreach(property_index RANGE 0 ${last_property_index})
            string(JSON current_property_name GET
                "${HELIX_CTEST_JSON}"
                tests ${test_index} properties ${property_index} name
            )
            if(current_property_name STREQUAL property_name)
                set(found TRUE)
                string(JSON value_type TYPE
                    "${HELIX_CTEST_JSON}"
                    tests ${test_index} properties ${property_index} value
                )

                if(value_type STREQUAL "ARRAY")
                    string(JSON value_count LENGTH
                        "${HELIX_CTEST_JSON}"
                        tests ${test_index} properties ${property_index} value
                    )
                    if(value_count GREATER 0)
                        math(EXPR last_value_index "${value_count} - 1")
                        foreach(value_index RANGE 0 ${last_value_index})
                            string(JSON current_value GET
                                "${HELIX_CTEST_JSON}"
                                tests ${test_index} properties ${property_index} value ${value_index}
                            )
                            list(APPEND values "${current_value}")
                        endforeach()
                    endif()
                else()
                    string(JSON current_value GET
                        "${HELIX_CTEST_JSON}"
                        tests ${test_index} properties ${property_index} value
                    )
                    list(APPEND values "${current_value}")
                endif()
            endif()
        endforeach()
    endif()

    set(${out_var} "${values}" PARENT_SCOPE)
    set(${out_var}_FOUND "${found}" PARENT_SCOPE)
endfunction()

helix_find_test_index("${HELIX_BENCHMARK_TEST_NAME}" benchmark_test_index)
helix_get_test_property(${benchmark_test_index} LABELS benchmark_labels)
if(NOT benchmark_labels_FOUND)
    message(FATAL_ERROR "${HELIX_BENCHMARK_TEST_NAME} has no LABELS property")
endif()

list(LENGTH benchmark_labels benchmark_label_count)
list(FIND benchmark_labels benchmark benchmark_label_index)
list(FIND benchmark_labels cuda benchmark_cuda_label_index)
if(NOT benchmark_label_count EQUAL 1 OR benchmark_label_index EQUAL -1)
    message(FATAL_ERROR
        "${HELIX_BENCHMARK_TEST_NAME} must have exactly the explicit benchmark label; got: ${benchmark_labels}"
    )
endif()
if(NOT benchmark_cuda_label_index EQUAL -1)
    message(FATAL_ERROR "${HELIX_BENCHMARK_TEST_NAME} must not be selected by the cuda correctness label")
endif()

helix_get_test_property(${benchmark_test_index} RESOURCE_LOCK benchmark_resource_lock)
if(NOT benchmark_resource_lock_FOUND)
    message(FATAL_ERROR "${HELIX_BENCHMARK_TEST_NAME} has no RESOURCE_LOCK property")
endif()
list(LENGTH benchmark_resource_lock benchmark_resource_lock_count)
list(FIND benchmark_resource_lock gpu benchmark_gpu_lock_index)
if(NOT benchmark_resource_lock_count EQUAL 1 OR benchmark_gpu_lock_index EQUAL -1)
    message(FATAL_ERROR
        "${HELIX_BENCHMARK_TEST_NAME} must use exactly RESOURCE_LOCK gpu; got: ${benchmark_resource_lock}"
    )
endif()

helix_find_test_index(v01_public_lifecycle_numerical_gate correctness_test_index)
helix_get_test_property(${correctness_test_index} LABELS correctness_labels)
list(FIND correctness_labels numerical correctness_numerical_label_index)
list(FIND correctness_labels cuda correctness_cuda_label_index)
if(correctness_numerical_label_index EQUAL -1 OR correctness_cuda_label_index EQUAL -1)
    message(FATAL_ERROR
        "ordinary GPU numerical tests must retain the numerical and auto-added cuda labels; got: ${correctness_labels}"
    )
endif()

file(READ "${HELIX_SOURCE_DIR}/.github/workflows/cuda-smoke.yml" cuda_workflow)
set(required_ordinary_selector [=[ctest --test-dir "${HELIX_BUILD_DIR}" --output-on-failure -LE "^(sanitizer|benchmark)$"]=])
string(FIND "${cuda_workflow}" "${required_ordinary_selector}" ordinary_selector_index)
if(ordinary_selector_index EQUAL -1)
    message(FATAL_ERROR "CUDA CI ordinary CTest selector must exclude exactly sanitizer and benchmark")
endif()

message(STATUS "CTest label/resource-lock review passed")
