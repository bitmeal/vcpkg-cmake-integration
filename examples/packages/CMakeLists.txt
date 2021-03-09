# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# 
# Copyright (C) 2020, Arne Wendt
#
cmake_minimum_required(VERSION 3.0.0)
set(CMAKE_CXX_STANDARD 11)

# init VCPKG [before call to project()]
set(VCPKG_VERSION latest)
include(../../vcpkg.cmake)

project(vcpkg-cmake-test VERSION 0.1.0)


# add packages
vcpkg_add_package(fmt)
vcpkg_add_package(plog)



find_package(fmt CONFIG REQUIRED)
find_path(PLOG_INCLUDE_DIRS "plog/Init.h")


# build "examples"
add_executable(fmt_test ../test-fmt.cpp)
target_link_libraries(fmt_test fmt::fmt)

add_executable(plog_test ../test-plog.cpp)
target_include_directories(plog_test PRIVATE ${PLOG_INCLUDE_DIRS})
