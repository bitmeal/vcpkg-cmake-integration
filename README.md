# vcpkg 💕 CMake integration
[![test](https://github.com/bitmeal/vcpkg-cmake-integration/actions/workflows/test.yaml/badge.svg)](https://github.com/bitmeal/vcpkg-cmake-integration/actions/workflows/test.yaml)
MSVC19@`windows-latest`(*Windows Server 2019*) + GCC 9.3@`ubuntu-latest`(*Ubuntu 20.04*)

---
**Buckle up and get lift:**
* add a copy of `vcpkg.cmake` to your project, or include as git-*submodule*
* add `include(vcpkg.cmake)` before your call to `project(...)` [in your top-level `CMakeListst.txt`]
* have a **`vcpkg.json` manifest** in your project?
  * **YES:** ***DONE!* 🚀**
  * **NO:** add packages by calling `vcpkg_add_package(<pkg_name>)`
* ***DONE!* 🚀**

```cmake
# EXAMPLE

set(VCPKG_VERSION edge) # optional
include(vcpkg.cmake)

project(awesome-project)

# without 'vcpkg.json'-manifest
vcpkg_add_package(fmt)

...
```

## What it does & intended use
* fetch *vcpkg* & build if required
* provide *"numeric"* or semantic versioning of *vcpkg* itself
* enable the *vcpkg*-*CMake* toolchain
* install all requested packages
* mask *musl-libc* from vcpkg as `x64-linux`/`x86-linux` and auto configure system binary usage ⚡

Intention of this script is to provide rapid setup and integration for *vcpkg* to kickstart your *C++* development on **(mainly) new** projects. Secondary use-case is sharing and reliable builds of projects by persons unfamiliar with *CMake* and managing dependencies for *C++* projects.

## using `vcpkg_add_package()`
This wrapper around `vcpkg install` makes the use of *vcpkg* completely transparent and is intended for the **setup and prototyping phase** of your project, allowing to focus on your build and not getting distracted by setting up package management systems.

What it does more, is **generating a `vcpkg.json`-manifest** in your build directory, *to be used at a later stage* of your project to pin dependencies!
> **📌 CMake 3.19 or later is required for automatic manifest generation!**

## using `vcpkg.json`-manifests
When a `vcpkg.json` manifest file is present, all packages from this manifest will be installed. Per default, `manifests` and `versions` features are enabled. **Using manifests is (at time of writing) still considered *experimental*. Using versioning and the `versions`-key may currently require a newer *vcpkg* version than tagged as latest release! Check the [official resources](https://github.com/microsoft/vcpkg) for the state of manifest use! The `edge`-version supports versioning, as per the examples/tests.**

> **ℹ To transition to manifests from `vcpkg_add_package()` calls, use the *auto-generated manifest in your build directory*.**

### manifests, CMake scripting mode & container layer caching
`vcpkg.cmake` can be called in *CMake* scripting mode to bootstrap *vcpkg* and install dependencies from a manifest. Allowing you to separate dependency installation and configuration of your project. This is mainly useful in building containers and not fetching and rebuilding all dependencies on every new build.
```shell
cmake -DVCPKG_PARENT_DIR=<path-to-build-directory> -P <path-to>/vcpkg.cmake
```
* **Set your build directory** using `-DVCPKG_PARENT_DIR=<path-to-build-directory>` (directory will be created if not exists)
* if your manifest has no `builtin-baseline`, set your *vcpkg* version as outlined below in ***vcpkg* versions** (`-DVCPKG_VERSION=<version>`)
* `VCPKG_TARGET_TRIPLET`/`VCPKG_DEFAULT_TRIPLET` CMake variables will set `ENV{VCPKG_DEFAULT_TRIPLET}`
* `VCPKG_HOST_TRIPLET`/`VCPKG_DEFAULT_HOST_TRIPLET` CMake variables will set `ENV{VCPKG_DEFAULT_HOST_TRIPLET}`

As no *CMake* configuration step is performed, *vcpkgs* own toolchain integration does not execute its magic itself, so be careful to set your target triplets accordingly.

#### container recipe
* `ADD` `vcpkg.json`-manifest to your project root inside the container
* `ADD` your copy of `vcpkg.cmake` to your container
* run `cmake -DVCPKG_PARENT_DIR=<path-to-build-directory> -DVCPKG_VERSION=<desired-vcpkg-version> -DVCPKG_DEFAULT_TRIPLET=<triplet> -P <path-to>/vcpkg.cmake` in your project root


## *vcpkg* versions
To set the desired *vcpkg* version use:
```cmake
set(VCPKG_VERSION <version>)
include(vcpkg.cmake)
```

Valid values for `<version>` are:
* `latest`: checks out latest tagged *vcpkg* version/release
* `<empty>`: gets you `latest`
* `edge`: latest commit on *vcpkg* master branch
* `<commit-hash>/<tag>`: any tag or commit hash from the *vcpkg*-repo may be used

> 📌 if a `vcpkg.json` manifest exists and specifies a `builtin-baseline`, this commit will be checked out
  
  
## setting target/host architecture
To manually configure/override target or host architecture, override these before your call to `include(vcpkg.cmake)`. If any of the following variables is set, no additional configuration will be performed. *Remember to set environment variables on every run, as they are not cached!*
* `ENV{VCPKG_DEFAULT_TRIPLET}`
* `ENV{VCPKG_DEFAULT_HOST_TRIPLET}`
* `VCPKG_TARGET_TRIPLET`


## required system libs
Yes, bootstrapping *vcpkg* only goes that far, but: Setting up a build system and dev environment is not *vcpkg*'s job.
*This is most relevant for use in build containers.* Most of the dependencies below are required to build C++ code in general and not *vcpkg* specific.

General requirements
* *C++* compiler toolchain
* *CMake*
* *Git*

### Ubuntu/Debian
```
apt install build-essential git cmake pkg-config curl zip unzip tar 
```

### alpine
Alpine uses `musl-libc` and can't use official binaries, as they are built against `glibc`. On alpine we detect `musl-libc` and need all system binaries available:
```
apk add build-base git cmake extra-cmake-modules abuild ninja curl zip
```
`musl-libc` will be masked as standard `x86-linux`/`x64-linux`, you may need to add extended compatibility (select right version):
```bash
# EXAMPLE
apk add libc6-compat
```


## ⚡ compatibility ⚡
**Unsure!**

Targeted platforms are "standard" Linux distros using *glibc* and Windows. Alpine, using *musl-libc*, is handled as an exception for its wide use in containerized applications. As long as the auto detected target-triplet of your platform is supported by *vcpkg* itself, no problems should arise.


## TODO
* testing *CMake* functions individually
* checkout `baseline` when version is unset and using manifest
