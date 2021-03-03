# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# 
# Copyright (C) 2021, Arne Wendt
#
cmake_minimum_required(VERSION 3.16.0)

# config:
# - VCPKG_VERSION:
#   - "latest": latest git tag (undefined or empty treated as "latest")
#   - "edge": last commit on master
# - VCPKG_PARENT_DIR: where to place vcpkg
# - VCPKG_FORCE_SYSTEM_BINARIES: use system cmake, zip, unzip, tar, etc.
#       may be necessary on some systems as downloaded binaries may be linked against unsupported libraries
#       musl-libc based distros (ALPINE)(!) require use of system binaries, but are AUTO DETECTED!
# - VCPKG_FEATURE_FLAGS: modify feature flags; default are "manifests,versions"
# 
# - VCPKG_NO_INIT: do not call vcpkg_init() automatically (for use testing)


# set default feature flags if not defined
if(NOT DEFINED VCPKG_FEATURE_FLAGS)
    set(VCPKG_FEATURE_FLAGS "manifests,versions" CACHE INTERNAL "necessary vcpkg flags for manifest based autoinstall and versioning")
endif()

# disable metrics by default
if(NOT DEFINED VCPKG_METRICS_FLAG)
    set(VCPKG_METRICS_FLAG "-disableMetrics" CACHE INTERNAL "flag to disable telemtry by default")
endif()


# get VCPKG
function(vcpkg_init)
    # test for vcpkg availability
    if(VCPKG_EXECUTABLE EQUAL "" OR NOT DEFINED VCPKG_EXECUTABLE)
        # set varible to expected path; necessary to detect after a CMake cache clean
        vcpkg_set_vcpkg_executable()
    endif()
    
    execute_process(COMMAND ${VCPKG_EXECUTABLE} version RESULT_VARIABLE VCPKG_TEST_RETVAL OUTPUT_VARIABLE VCPKG_VERSION_BANNER)
    if(NOT VCPKG_TEST_RETVAL EQUAL "0")
        # reset executable path
        set(VCPKG_EXECUTABLE "")

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
            set(VCPKG_BUILD_CMD ".\\bootstrap-vcpkg.bat")
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
            GIT_PROGRESS true

            SOURCE_DIR "${VCPKG_PARENT_DIR}/vcpkg"
            BINARY_DIR ""
            BUILD_IN_SOURCE true
            CONFIGURE_COMMAND ""
            BUILD_COMMAND ""
        )
        FetchContent_Populate(vcpkg)

        # use system binaries?
        # IMPORTANT: we have to use system binaries on musl-libc systems, as vcpkg fetches binaries linked against glibc!
        vcpkg_set_use_system_binaries_flag()

        # compute git checkout target
        vcpkg_set_version_checkout()

        # checkout asked version
        execute_process(COMMAND git checkout ${VCPKG_VERSION_CHECKOUT} WORKING_DIRECTORY "${VCPKG_PARENT_DIR}/vcpkg" RESULT_VARIABLE VCPKG_GIT_TAG_CHECKOUT_OK)
        if(NOT VCPKG_GIT_TAG_CHECKOUT_OK EQUAL "0")
            message(FATAL_ERROR "Checking out VCPKG version/tag ${VCPKG_VERSION} failed!")
        endif()

        # wrap -disableMetrics in extra single quotes for windows
        # if(WIN32 AND NOT VCPKG_METRICS_FLAG EQUAL "" AND DEFINED VCPKG_METRICS_FLAG)
        #     set(VCPKG_METRICS_FLAG "'${VCPKG_METRICS_FLAG}'")
        # endif()

        # build vcpkg
        execute_process(COMMAND ${VCPKG_BUILD_CMD} ${VCPKG_USE_SYSTEM_BINARIES_FLAG} ${VCPKG_METRICS_FLAG} WORKING_DIRECTORY "${VCPKG_PARENT_DIR}/vcpkg" RESULT_VARIABLE VCPKG_BUILD_OK)
        if(NOT VCPKG_BUILD_OK EQUAL "0")
            message(FATAL_ERROR "Bootstrapping VCPKG failed!")
        else()
            message(STATUS "Built VCPKG!")
        endif()


        # get vcpkg path
        vcpkg_set_vcpkg_executable()

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
    
    # mask musl-libc
    vcpkg_mask_if_musl_libc()

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

# set VCPKG_EXECUTABLE to assumed path based on VCPKG_PARENT_DIR
# vcpkg_set_vcpkg_executable([VCPKG_PARENT_DIR_EXPLICIT])
function(vcpkg_set_vcpkg_executable)
    if(ARGV0 EQUAL "" OR NOT DEFINED ARGV0)
        set(VCPKG_PARENT_DIR_EXPLICIT ${VCPKG_PARENT_DIR})
    else()
        set(VCPKG_PARENT_DIR_EXPLICIT ${ARGV0})
    endif()

    if(WIN32)
        set(VCPKG_EXECUTABLE "${VCPKG_PARENT_DIR_EXPLICIT}/vcpkg/vcpkg.exe" PARENT_SCOPE)
    else()
        set(VCPKG_EXECUTABLE "${VCPKG_PARENT_DIR_EXPLICIT}/vcpkg/vcpkg" PARENT_SCOPE)
    endif()
endfunction()

# determine git checkout target in: VCPKG_VERSION_CHECKOUT
# vcpkg_set_version_checkout([VCPKG_VERSION_EXPLICIT] [VCPKG_PARENT_DIR_EXPLICIT])
# TODO: set hash from vcpkg.json manifest if version==""
function(vcpkg_set_version_checkout)
    if(ARGV0 EQUAL "" OR NOT DEFINED ARGV0)
        set(VCPKG_VERSION_EXPLICIT ${VCPKG_VERSION})
    else()
        set(VCPKG_VERSION_EXPLICIT ${ARGV0})
    endif()
    if(ARGV1 EQUAL "" OR NOT DEFINED ARGV1)
        set(VCPKG_PARENT_DIR_EXPLICIT ${VCPKG_PARENT_DIR})
    else()
        set(VCPKG_PARENT_DIR_EXPLICIT ${ARGV1})
    endif()

    # get latest git tag
    execute_process(COMMAND git for-each-ref refs/tags/ --count=1 --sort=-creatordate --format=%\(refname:short\) WORKING_DIRECTORY "${VCPKG_PARENT_DIR_EXPLICIT}/vcpkg" OUTPUT_VARIABLE VCPKG_GIT_TAG_LATEST)
    string(REGEX REPLACE "\n$" "" VCPKG_GIT_TAG_LATEST "${VCPKG_GIT_TAG_LATEST}")

    # resolve versions
    if("${VCPKG_VERSION_EXPLICIT}" STREQUAL "latest" OR "${VCPKG_VERSION_EXPLICIT}" EQUAL "" OR NOT DEFINED VCPKG_VERSION_EXPLICIT)
        set(VCPKG_VERSION_CHECKOUT ${VCPKG_GIT_TAG_LATEST})
        message(STATUS "Using VCPKG Version: ${VCPKG_VERSION_EXPLICIT} (latest)")
    elseif("${VCPKG_VERSION_EXPLICIT}" STREQUAL "edge" OR "${VCPKG_VERSION_EXPLICIT}" STREQUAL "master")
        set(VCPKG_VERSION_CHECKOUT "master")
        message(STATUS "Using VCPKG Version: edge (latest commit)")
    else()
        message(STATUS "Using VCPKG Version: ${VCPKG_VERSION_EXPLICIT}")
        set(VCPKG_VERSION_CHECKOUT ${VCPKG_VERSION_EXPLICIT})
    endif()

    set(VCPKG_VERSION_CHECKOUT ${VCPKG_VERSION_CHECKOUT} PARENT_SCOPE)
endfunction()

# sets VCPKG_PLATFORM_MUSL_LIBC(ON|OFF)
function(vcpkg_get_set_musl_libc)
    if(WIN32)
        # is windows
        set(VCPKG_PLATFORM_MUSL_LIBC OFF)
    else()
        execute_process(COMMAND getconf GNU_LIBC_VERSION RESULT_VARIABLE VCPKG_PLATFORM_GLIBC)
        if(VCPKG_PLATFORM_GLIBC EQUAL "0")
            # has glibc
            set(VCPKG_PLATFORM_MUSL_LIBC OFF)
        else()
            execute_process(COMMAND ldd --version RESULT_VARIABLE VCPKG_PLATFORM_LDD_OK OUTPUT_VARIABLE VCPKG_PLATFORM_LDD_VERSION_STDOUT ERROR_VARIABLE VCPKG_PLATFORM_LDD_VERSION_STDERR)
            string(TOLOWER "${VCPKG_PLATFORM_LDD_VERSION_STDOUT}" VCPKG_PLATFORM_LDD_VERSION_STDOUT)
            string(TOLOWER "${VCPKG_PLATFORM_LDD_VERSION_STDERR}" VCPKG_PLATFORM_LDD_VERSION_STDERR)
            string(FIND "${VCPKG_PLATFORM_LDD_VERSION_STDOUT}" "musl" VCPKG_PLATFORM_LDD_FIND_MUSL_STDOUT)
            string(FIND "${VCPKG_PLATFORM_LDD_VERSION_STDERR}" "musl" VCPKG_PLATFORM_LDD_FIND_MUSL_STDERR)
            if(
                (VCPKG_PLATFORM_LDD_OK EQUAL "0" AND NOT VCPKG_PLATFORM_LDD_FIND_MUSL_STDOUT EQUAL "-1") OR
                (NOT VCPKG_PLATFORM_LDD_OK EQUAL "0" AND NOT VCPKG_PLATFORM_LDD_FIND_MUSL_STDERR EQUAL "-1")
            )
                # has musl-libc
                # use system binaries
                set(VCPKG_PLATFORM_MUSL_LIBC ON)
                message(STATUS "VCPKG: System is using musl-libc; using system binaries! (e.g. cmake, curl, zip, tar, etc.)")
            else()
                # has error...
                message(FATAL_ERROR "VCPKG: could detect neither glibc nor musl-libc!")
            endif()
        endif()
    endif()

    # propagate back
    set(VCPKG_PLATFORM_MUSL_LIBC ${VCPKG_PLATFORM_MUSL_LIBC} PARENT_SCOPE)
endfunction()


# configure environment and CMake variables to mask musl-libc from vcpkg triplet checks
function(vcpkg_mask_musl_libc)
    # set target triplet without '-musl'
    execute_process(COMMAND ldd --version RESULT_VARIABLE VCPKG_PLATFORM_LDD_OK OUTPUT_VARIABLE VCPKG_PLATFORM_LDD_VERSION_STDOUT ERROR_VARIABLE VCPKG_PLATFORM_LDD_VERSION_STDERR)
    string(TOLOWER "${VCPKG_PLATFORM_LDD_VERSION_STDOUT}" VCPKG_PLATFORM_LDD_VERSION_STDOUT)
    string(TOLOWER "${VCPKG_PLATFORM_LDD_VERSION_STDERR}" VCPKG_PLATFORM_LDD_VERSION_STDERR)
    string(FIND "${VCPKG_PLATFORM_LDD_VERSION_STDOUT}" "x86_64" VCPKG_PLATFORM_LDD_FIND_MUSL_BITS_STDOUT)
    string(FIND "${VCPKG_PLATFORM_LDD_VERSION_STDERR}" "x86_64" VCPKG_PLATFORM_LDD_FIND_MUSL_BITS_STDERR)
    if(
        NOT VCPKG_PLATFORM_LDD_FIND_MUSL_BITS_STDOUT EQUAL "-1" OR
        NOT VCPKG_PLATFORM_LDD_FIND_MUSL_BITS_STDERR EQUAL "-1"
    )
        set(VCPKG_TARGET_TRIPLET "x64-linux")
    else()
        set(VCPKG_TARGET_TRIPLET "x86-linux")
    endif()

    set(ENV{VCPKG_DEFAULT_TRIPLET} "${VCPKG_TARGET_TRIPLET}")
    set(ENV{VCPKG_DEFAULT_HOST_TRIPLET} "${VCPKG_TARGET_TRIPLET}")
    set(VCPKG_TARGET_TRIPLET "${VCPKG_TARGET_TRIPLET}" CACHE STRING "vcpkg default target triplet (possibly dont change)")
    message(STATUS "VCPKG: System is using musl-libc; fixing default target triplet as: ${VCPKG_TARGET_TRIPLET}")
endfunction()

# automate musl-libc masking
function(vcpkg_mask_if_musl_libc)
    vcpkg_get_set_musl_libc()
    if(VCPKG_PLATFORM_MUSL_LIBC)
        vcpkg_mask_musl_libc()
    endif()
endfunction()

# sets VCPKG_USE_SYSTEM_BINARIES_FLAG from VCPKG_PLATFORM_MUSL_LIBC and/or VCPKG_FORCE_SYSTEM_BINARIES
# vcpkg_set_use_system_binaries_flag([VCPKG_FORCE_SYSTEM_BINARIES_EXPLICIT])
function(vcpkg_set_use_system_binaries_flag)
    if(ARGV0 EQUAL "" OR NOT DEFINED ARGV0)
        set(VCPKG_FORCE_SYSTEM_BINARIES_EXPLICIT ${VCPKG_FORCE_SYSTEM_BINARIES})
    else()
        set(VCPKG_FORCE_SYSTEM_BINARIES_EXPLICIT ${ARGV0})
    endif()

    vcpkg_get_set_musl_libc()

    if(NOT WIN32 AND (VCPKG_FORCE_SYSTEM_BINARIES_EXPLICIT OR VCPKG_PLATFORM_MUSL_LIBC) )
        set(VCPKG_USE_SYSTEM_BINARIES_FLAG "--useSystemBinaries" PARENT_SCOPE)
        # has to be propagated to all install calls
        set(ENV{VCPKG_FORCE_SYSTEM_BINARIES} "1")
        set(VCPKG_FORCE_SYSTEM_BINARIES ON CACHE BOOL "force vcpkg to use system binaries (possibly dont change)")

        message(STATUS "VCPKG: Requested use of system binaries! (e.g. cmake, curl, zip, tar, etc.)")
    else()
        set(VCPKG_USE_SYSTEM_BINARIES_FLAG "" PARENT_SCOPE)
    endif()
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


# get vcpkg and configure toolchain
if(NOT VCPKG_NO_INIT)
    vcpkg_init()
endif()
