# auto generated manifest
Uses same setup as `packages` test, but for testing the automatically generated manifest from calls to `vcpkg_add_package()`.

* call with `-DVCPKG_ADD_PACKAGES=true` to use `vcpkg_add_package()` and generate manifest
* copy `build/vcpkg.json` to `CMakeLists.txt` directory
* remove `build/` directory
* build again without `-DVCPKG_ADD_PACKAGES=true`; or set `-DVCPKG_ADD_PACKAGES=false`