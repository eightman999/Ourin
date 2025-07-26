cmake_minimum_required(VERSION 3.22)
project(MyPlugin C)

# Build as Universal 2 (arm64 + x86_64)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")

add_library(MyPlugin MODULE plugin.c)
# Bundle .plugin with Info.plist
set_target_properties(MyPlugin PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "plugin"
  OUTPUT_NAME "MyPlugin"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
)

# Install into a PlugIns folder (optional)
install(TARGETS MyPlugin BUNDLE DESTINATION "PlugIns")


# Link iconv for CP932<->UTF-8 conversion
find_library(ICONV_LIBRARY iconv)
if(ICONV_LIBRARY)
  target_link_libraries(MyPlugin PRIVATE ${ICONV_LIBRARY})
endif()
