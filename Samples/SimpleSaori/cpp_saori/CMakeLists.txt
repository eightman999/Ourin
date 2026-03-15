cmake_minimum_required(VERSION 3.18)
project(SimpleSaoriCpp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")

add_library(SimpleSaoriCpp SHARED saori.cpp)
set_target_properties(SimpleSaoriCpp PROPERTIES
  OUTPUT_NAME "simple_saori_cpp"
  PREFIX ""
)

