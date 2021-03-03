# vcpkg 💕 CMake integration
Buckle up and get lift
* add `include(vcpkg.cmake)` before your call to `project(...)` (in your top-level `CMakeListst.txt`)
* have a **`vcpkg.json` manifest** in your project?
  * YES: **DONE! 🚀**
  * NO: add packages by calling `vcpkg_add_package(<pkg_name>)`
* **DONE! 🚀**

```cmake
# EXAMPLE

set(VCPKG_VERSION edge)
include(vcpkg.cmake)

project(awesome-project)

...
```

What does it do?
* fetch *vcpkg*
* build *vcpkg* if required
* *"numeric"*  or semantic versioning of *vcpkg* itself
* mask *musl-libc* from vcpkg as `x64-linux`/`x86-linux` ⚡
* enable the *vcpkg*-*CMake* toolchain
* installs all requested packages
  
  
## using `vcpkg.json`-manifests
When a `vcpkg.json` manifest file is present, all packages from this manifest will be installed. Per default, `manifests` and `versions` features are enabled. Using `versions` currently requires a newer *vcpkg* version than tagged. Be sure to use version `edge` as per the examples.
  

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
  
  
## required system libs
Yes, bootstrapping *vcpkg* only goes that far, but: Setting up a build system and dev environment is not *vcpk*s job.
*This is most relevant for use in build containers.* Most of the dependencies below are required to build C++ code in general and not *vcpkg* specific.

### Ubuntu/Debian
```
apt install build-essential git cmake pkg-config curl zip unzip tar 
```

### alpine
Alpine uses `musl-libc` and can't use official binaries, as they are built against `glibc`. On alpine we detect `musl-libc` and need all system binaries available:
```
apk add build-base git cmake extra-cmake-modules abuild ninja curl
```
`musl-libc` will be masked as standard `x86-linux`/`x64-linux`, you may need to add extended compatibility (select right version):
```bash
# EXAMPLE
apk add libc6-compat
```


## ⚡ compatibility ⚡
**Unsure!**
  
  
Targeted platforms are "standard" Linux distros using *glibc* and Windows. Alpine, using *musl-libc*, is handled as an exception for its wide use in containerized applications.

**Expect** everything **other** than these target triplets to **break**:
* `x86-linux`
* `x64-linux`
* `x86-windows`
* `x64-windows`
* `[x86-linux-musl]` *masked*
* `[x64-linux-musl]` *masked*



## TODO
* testing *CMake* function individually
* cache handling
* check if target triplets may be set by user or are overwritten
* checkout `baseline` when version is unset and using manifest
* detect OSX