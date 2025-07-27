cmake_minimum_required(VERSION 3.18)
project(OurinSampleSHIORI C)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")
add_library(OurinSampleSHIORI MODULE shiori.c)
set_target_properties(OurinSampleSHIORI PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "bundle"
  OUTPUT_NAME "OurinSampleSHIORI"
)
