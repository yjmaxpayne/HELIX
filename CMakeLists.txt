cmake_minimum_required(VERSION 3.24)

project(HELIX LANGUAGES CXX CUDA)

find_package(CUDAToolkit REQUIRED)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

set(HELIX_CUDA_ARCHITECTURES "native" CACHE STRING "CUDA architectures for HELIX")
if(DEFINED HEOM_CUDA_ARCHITECTURES)
    set(HELIX_CUDA_ARCHITECTURES "${HEOM_CUDA_ARCHITECTURES}" CACHE STRING "CUDA architectures for HELIX" FORCE)
endif()

add_executable(helix
    src/Main.cu
    src/Initialize.cu
    src/Liouville.cu
    src/Matrixes.cu
    src/MatrixUtil.cu
    src/Parameters.cu
    src/Psd/Eigval.cu
    src/Psd/Psd.cu
)

target_include_directories(helix PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(helix PRIVATE
    CUDA::cublas
    CUDA::cusparse
)

set_target_properties(helix PROPERTIES
    CUDA_ARCHITECTURES "${HELIX_CUDA_ARCHITECTURES}"
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_RESOLVE_DEVICE_SYMBOLS ON
)
