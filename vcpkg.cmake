# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# 
# Copyright (C) 2021, Arne Wendt
#
cmake_minimum_required(VERSION 3.12.0)

set(VCPKG_FEATURE_FLAGS "manifests,versions" INTERNAL "necessary vcpkg flags for manifest based autoinstall and versioning")
# set(VCPKG_FEATURE_FLAGS "manifests,versions")


## get VCPKG
# config:
# - VCPKG_VERSION:
#   - "latest": latest git tag (undefined or empty treated as "latest")
#   - "edge": last commit on master
# - VCPKG_PARENT_DIR: where to place vcpkg
#
function(vcpkg_init)
    # test for vcpkg availability
    if(VCPKG_EXECUTABLE EQUAL "" OR NOT DEFINED VCPKG_EXECUTABLE)
        set(VCPKG_EXECUTABLE "")
        set(VCPKG_TEST_RETVAL "1")
    else()
        execute_process(COMMAND ${VCPKG_EXECUTABLE} version RESULT_VARIABLE VCPKG_TEST_RETVAL OUTPUT_VARIABLE VCPKG_VERSION_BANNER)
    endif()

    # test for vcpkg availability - stage 2
    if(VCPKG_EXECUTABLE EQUAL "" OR NOT VCPKG_TEST_RETVAL EQUAL "0")
        ## getting vcpkg
        message(STATUS "No VCPKG found; getting new version ready...")

        # test options
        if(VCPKG_PARENT_DIR EQUAL "" OR NOT DEFINED VCPKG_PARENT_DIR)
            message(STATUS "Placing VCPKG in: ${CMAKE_CURRENT_BINARY_DIR}")
            set(VCPKG_PARENT_DIR "${CMAKE_CURRENT_BINARY_DIR}/")
        endif()
        string(REGEX REPLACE "[/\\]$" "" VCPKG_PARENT_DIR "${VCPKG_PARENT_DIR}")

        # select compile script
        if(WIN32)
            set(VCPKG_BUILD_CMD "bootstrap-vcpkg.bat")
        else()
            set(VCPKG_BUILD_CMD "./bootstrap-vcpkg.sh")
        endif()

        # prepare and clone git sources
        # clone to: <project>/deps/vcpkg
        include(FetchContent)
        set(FETCHCONTENT_QUIET on)
        set(FETCHCONTENT_BASE_DIR "${VCPKG_PARENT_DIR}")
        FetchContent_Declare(
            vcpkg

            GIT_REPOSITORY "https://github.com/microsoft/vcpkg"
            # GIT_TAG  "${VCPKG_VERSION}"
            GIT_PROGRESS true

            SOURCE_DIR "${VCPKG_PARENT_DIR}/vcpkg"
            BINARY_DIR ""
            BUILD_IN_SOURCE true
            CONFIGURE_COMMAND ""
            BUILD_COMMAND ""
        )
        FetchContent_Populate(vcpkg)

        # get latest git tag
        execute_process(COMMAND git for-each-ref refs/tags/ --count=1 --sort=-creatordate --format=%\(refname:short\) WORKING_DIRECTORY "${VCPKG_PARENT_DIR}/vcpkg" OUTPUT_VARIABLE VCPKG_GIT_TAG_LATEST)
        string(REGEX REPLACE "\n$" "" VCPKG_GIT_TAG_LATEST "${VCPKG_GIT_TAG_LATEST}")

        # resolve versions
        if("${VCPKG_VERSION}" STREQUAL "latest" OR "${VCPKG_VERSION}" EQUAL "" OR NOT DEFINED VCPKG_VERSION)
            set(VCPKG_VERSION ${VCPKG_GIT_TAG_LATEST})
            message(STATUS "Using VCPKG Version: ${VCPKG_VERSION} (latest)")
        elseif("${VCPKG_VERSION}" STREQUAL "edge" OR "${VCPKG_VERSION}" STREQUAL "master")
            set(VCPKG_VERSION "master")
            message(STATUS "Using VCPKG Version: edge (latest commit)")
        else()
            message(STATUS "Using VCPKG Version: ${VCPKG_VERSION}")
        endif()

        # checkout asked version
        execute_process(COMMAND git checkout ${VCPKG_VERSION} WORKING_DIRECTORY "${VCPKG_PARENT_DIR}/vcpkg" RESULT_VARIABLE VCPKG_GIT_TAG_CHECKOUT_OK)
        if(NOT VCPKG_GIT_TAG_CHECKOUT_OK EQUAL "0")
            message(FATAL_ERROR "Checking out VCPKG version/tag ${VCPKG_VERSION} failed!")
        endif()

        # build vcpkg
        execute_process(COMMAND ${VCPKG_BUILD_CMD} WORKING_DIRECTORY "${VCPKG_PARENT_DIR}/vcpkg" RESULT_VARIABLE VCPKG_BUILD_OK)
        if(NOT VCPKG_BUILD_OK EQUAL "0")
            message(FATAL_ERROR "Bootstrapping VCPKG failed!")
        else()
            message(STATUS "Built VCPKG!")
        endif()


        # get vcpkg path
        if(WIN32)
            set(VCPKG_EXECUTABLE "${VCPKG_PARENT_DIR}/vcpkg/vcpkg.exe")
        else()
            set(VCPKG_EXECUTABLE "${VCPKG_PARENT_DIR}/vcpkg/vcpkg")
        endif()

        # test vcpkg binary
        execute_process(COMMAND ${VCPKG_EXECUTABLE} version RESULT_VARIABLE VCPKG_OK OUTPUT_VARIABLE VCPKG_VERSION_BANNER)
        if(NOT VCPKG_OK EQUAL "0")
            message(FATAL_ERROR "VCPKG executable failed test!")
        else()
            message(STATUS "VCPKG ready!")
            string(REGEX REPLACE "\n$" "" VCPKG_VERSION_BANNER "${VCPKG_VERSION_BANNER}")
            string(REGEX REPLACE "\n\n" " / " VCPKG_VERSION_BANNER "${VCPKG_VERSION_BANNER}")
            message(STATUS "${VCPKG_VERSION_BANNER}")

            set(VCPKG_EXECUTABLE ${VCPKG_EXECUTABLE} CACHE STRING "vcpkg executable path" FORCE)

            message(STATUS "Install packages using VCPKG:")
            message(STATUS " * from your CMakeLists.txt by calling vcpkg_add_package(<PKG_NAME>)")
            message(STATUS " * by providing a 'vcpkg.json' in your project directory [https://devblogs.microsoft.com/cppblog/take-control-of-your-vcpkg-dependencies-with-versioning-support/]")
        endif()
    else()
        # version banner is set while testing for availability
        message(STATUS "VCPKG using:")
        string(REGEX REPLACE "\n.*$" "" VCPKG_VERSION_BANNER "${VCPKG_VERSION_BANNER}")
        message(STATUS "${VCPKG_VERSION_BANNER}")
    endif()

    set(VCPKG_EXECUTABLE ${VCPKG_EXECUTABLE} PARENT_SCOPE)
    
    # set toolchain
    set(CMAKE_TOOLCHAIN_FILE "${VCPKG_PARENT_DIR}/vcpkg/scripts/buildsystems/vcpkg.cmake")
    set(CMAKE_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} PARENT_SCOPE)
    set(CMAKE_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} CACHE STRING "")
endfunction()


# make target triplet from current compiler selection and platform
# set VCPKG_TARGET_TRIPLET in parent scope
function(vcpkg_make_set_triplet)
    # get platform: win/linux ONLY
    if(WIN32)
        set(PLATFORM "windows")
    else()
        set(PLATFORM "linux")
    endif()

    # get bitness: 32/64 ONLY
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(BITS 64)
    else()
        set(BITS 86)
    endif()

    set(VCPKG_TARGET_TRIPLET "x${BITS}-${PLATFORM}" PARENT_SCOPE)
endfunction()


# install package
function(vcpkg_add_package PKG_NAME)
    if(VCPKG_TARGET_TRIPLET STREQUAL "" OR NOT DEFINED VCPKG_TARGET_TRIPLET)
        vcpkg_make_set_triplet()
    endif()

    message(STATUS "VCPKG: fetching ${PKG_NAME} via vcpkg_add_package")
    execute_process(COMMAND ${VCPKG_EXECUTABLE} --triplet=${VCPKG_TARGET_TRIPLET} --feature-flags=-manifests --disable-metrics install "${PKG_NAME}" WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} RESULT_VARIABLE VCPKG_INSTALL_OK)
    if(NOT VCPKG_INSTALL_OK EQUAL "0")
        message(FATAL_ERROR "VCPKG: failed fetching ${PKG_NAME}! Did you call vcpkg_init(<...>)?")
    endif()
endfunction()


# # install packages from manifest
# function(vcpkg_install_manifest)
#     if(VCPKG_TARGET_TRIPLET STREQUAL "" OR NOT DEFINED VCPKG_TARGET_TRIPLET)
#         vcpkg_make_set_triplet()
#     endif()
#     
#     message(STATUS "VCPKG: install from manifest; using target triplet: ${VCPKG_TARGET_TRIPLET}")
#     execute_process(COMMAND ${VCPKG_EXECUTABLE} --triplet=${VCPKG_TARGET_TRIPLET} --feature-flags=manifests,versions --disable-metrics install WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} RESULT_VARIABLE VCPKG_INSTALL_OK)
#     if(NOT VCPKG_INSTALL_OK EQUAL "0")
#         message(FATAL_ERROR "VCPKG: install from manifest failed")
#     endif()
# endfunction()

vcpkg_init()
