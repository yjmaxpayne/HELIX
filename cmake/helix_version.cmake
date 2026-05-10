set(HELIX_VERSION_FALLBACK "0.0.1" CACHE STRING "Fallback HELIX version when no release tag is available")
set(HELIX_RELEASE_VERSION "" CACHE STRING "Explicit HELIX release version, usually vMAJOR.MINOR.PATCH")

function(helix_set_version_from_string candidate source)
    string(STRIP "${candidate}" candidate)
    string(REGEX REPLACE "^v" "" normalized "${candidate}")

    if(NOT normalized MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\\+[0-9A-Za-z][0-9A-Za-z.-]*)?$")
        message(FATAL_ERROR "Invalid HELIX version from ${source}: ${candidate}")
    endif()

    set(HELIX_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}" PARENT_SCOPE)
    set(HELIX_VERSION_STRING "${normalized}" PARENT_SCOPE)
    set(HELIX_VERSION_SOURCE "${source}" PARENT_SCOPE)
endfunction()

if(HELIX_RELEASE_VERSION)
    helix_set_version_from_string("${HELIX_RELEASE_VERSION}" "HELIX_RELEASE_VERSION")
elseif(DEFINED ENV{HELIX_RELEASE_VERSION} AND NOT "$ENV{HELIX_RELEASE_VERSION}" STREQUAL "")
    helix_set_version_from_string("$ENV{HELIX_RELEASE_VERSION}" "HELIX_RELEASE_VERSION environment")
else()
    find_package(Git QUIET)
    if(Git_FOUND)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" describe --tags --match "v[0-9]*" --dirty --always
            WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/.."
            RESULT_VARIABLE HELIX_GIT_DESCRIBE_RESULT
            OUTPUT_VARIABLE HELIX_GIT_DESCRIBE
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
    endif()

    if(HELIX_GIT_DESCRIBE_RESULT EQUAL 0 AND HELIX_GIT_DESCRIBE MATCHES "^v?([0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?)(-dirty)?$")
        helix_set_version_from_string("${CMAKE_MATCH_1}" "git tag")
    elseif(HELIX_GIT_DESCRIBE_RESULT EQUAL 0 AND HELIX_GIT_DESCRIBE MATCHES "^v?([0-9]+\\.[0-9]+\\.[0-9]+)(-[0-9A-Za-z][0-9A-Za-z.-]*)?-([0-9]+)-g([0-9A-Fa-f]+)(-dirty)?$")
        set(version_candidate "${CMAKE_MATCH_1}+${CMAKE_MATCH_3}.g${CMAKE_MATCH_4}")
        if(CMAKE_MATCH_5)
            string(APPEND version_candidate ".dirty")
        endif()
        helix_set_version_from_string("${version_candidate}" "git describe")
    else()
        helix_set_version_from_string("${HELIX_VERSION_FALLBACK}" "fallback")
    endif()
endif()
