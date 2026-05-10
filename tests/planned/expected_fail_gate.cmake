cmake_minimum_required(VERSION 3.24)

foreach(required_var IN ITEMS HELIX_GATE_NAME HELIX_GATE_TASK HELIX_GATE_REASON)
    if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
        message(FATAL_ERROR "Expected-fail gate script requires ${required_var}")
    endif()
endforeach()

message(FATAL_ERROR
    "HELIX v0.1 planned gate '${HELIX_GATE_NAME}' is intentionally red for "
    "${HELIX_GATE_TASK}: ${HELIX_GATE_REASON}"
)
