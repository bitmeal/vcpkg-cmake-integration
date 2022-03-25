# to be included as common build and test facility by individual tests
set(CMAKE_CXX_STANDARD 11)
project(vcpkg-cmake-test-common VERSION 0.1.0)

## resolve dependencies
find_package(fmt REQUIRED)
find_path(PLOG_INCLUDE_DIRS "plog/Init.h" REQUIRED)


## build "tests/examples"
add_executable(fmt_test test-fmt.cpp)
target_link_libraries(fmt_test fmt::fmt)

add_executable(plog_test test-plog.cpp)
target_include_directories(plog_test PRIVATE ${PLOG_INCLUDE_DIRS})


## testing
enable_testing()

# test for exit code only
add_test(NAME fmt-test COMMAND fmt_test)
add_test(NAME plog-test COMMAND plog_test)
