# saintonge-build
Saintonge-build provides a rudimentary command-line environment
for running out-of-source builds using Windows+msbuild+CMake,
with simple commands and some basic conventions.

## What Saintonge provides
* A simple PowerShell-based build environment
* Basic build commands
  - build -Clean / -Build / -Full / -Arch x86|x86 / -Flavor Debug|Release / -LogLevel (...)
  - Launch-VisualStudio
* Basic support for multiple projects, or building the same
  CMake project with different sets of generator options
  - dwb.projects.xml : Define projects by name, path to root CMakeLists, and generator options
  - Get-Project / Enable-Project / Disable-Project / Focus-Project
* Dependency delivery via NuGet, robocopy
  - build -Purge / -Restore
  - NuGet: Define dependencies in nuget.config, packages.config
* CMake functions for common Windows tasks in Saintonge.cmake
  - target_enable_pch(target pchname.h) : Enable precompiled header with
    whatever name
  - set_3264(myvar value32 value64) : Set a variable differently for 32-bit or
    64-bit builds
  - add_midl_target(targetname myidlfile.idl) : Adds an IDL target as a UTILITY
    target.

## Installing saintonge-build
1. Install the prerequisites:
    - Visual Studio or the Visual C++ build tools
      - Set VSTOOLS to the folder that contains VsDevCmd.bat
    - (Optional) CMake for Windows: If you want a version newer than the one that comes with VC++.
      - Set CMAKE_PATH to the cmake\bin folder.
    - (Optional) Doxygen.
      - Set DOXYGEN_PATH to the doxygen bin folder.
2. Bring your own project repo, in a folder like D:\bench.
3. Clone saintonge-build as a submodule of your repo, like D:\bench\build.
4. Create dwb.projects.xml in the root of your repo, with the path to each root CMakeLists.txt file.
    - Example: <dwb-workbench><project name="helloworld" path="src/helloworld" /></dwb-workbench>
5. Create a shortcut for your build prompt:
    - Target: cmd.exe /k build\setenv.bat & powershell -ExecutionPolicy Bypass -Command ". build\BuildCpp.ps1"
    - Start in: Your repo, e.g. D:\bench
6. Double-click your shortcut to launch your build prompt.

## Recommended project layout
 - build: Saintonge as a submodule
 - obj: Generated: Intermediate build output (Object tree)
 - bin: Generated: Binaries
 - ext: External dependencies (submodules, checked-in sources, nuget configs, etc.)
 - ext/lib: where Saintonge puts managed external dependencies

## Managing Dependencies
1. Using NuGet:
   - Define your nuget.config and packages.config as usual
   - Custom extensions to packages.config: <package id="MyLibBlah" version="1.2.3.4" shortname="blah" focus="src" />
      - NuGet installs into ext/lib/nuget.packages/MyLibBlah.1.2.3.4
      - Saintonge creates a symlink from ext/lib/blah -> ext/lib/nuget.packages/MyLibBlah.1.2.3.4/src
2. Using vcpkg: Set the VCPKG_PATH envvar prior to launch, and your vcpkg.cmake will be automatically brought in to all targets.
3. Using robocopy:
   - Intended for pulling external files into your workbench when they may be
     managed by some other solution

