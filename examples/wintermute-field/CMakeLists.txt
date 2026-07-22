cmake_minimum_required(VERSION 3.20)
project(wintermute_field CUDA CXX)

find_package(CUDAToolkit REQUIRED)

add_executable(wintermute-field field.cu)
set_target_properties(wintermute-field PROPERTIES
  CUDA_STANDARD 20
  CXX_STANDARD 20
)
install(TARGETS wintermute-field RUNTIME DESTINATION bin)
