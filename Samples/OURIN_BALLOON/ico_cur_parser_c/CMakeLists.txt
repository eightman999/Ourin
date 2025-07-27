
cmake_minimum_required(VERSION 3.18)
project(OurinIcoCur C)
add_library(ourin_icocur STATIC ico_cur.c)
target_include_directories(ourin_icocur PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")
