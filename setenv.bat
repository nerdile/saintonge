@echo off
set SGE_TOOLS=%~dp0
set SGE_TOOLS=%SGE_TOOLS:~0,-1%

REM Give CMAKE_PATH preference over the version of CMake that comes with Visual Studio
if not "%CMAKE_PATH%"=="" (set PATH=%PATH%;%CMAKE_PATH%)

where cl.exe >nul 2>nul || call :find_cl || exit /b 1
where cmake.exe >nul 2>nul || call :find_cmake || exit /b 1
where doxygen.exe >nul 2>nul || call :find_doxygen || (echo Doxygen functionality may not be available if your build depends on it.)
set path=%SGE_TOOLS%\scripts;%PATH%
if defined VCPKG_PATH set path=%PATH%;%VCPKG_PATH%\installed\x64-windows\tools;%VCPKG_PATH%\installed\x86-windows\tools

echo OK: Build environment ready.
exit /b 0


:find_cl
call :find_cl_in "%VSTOOLS%" || call :find_cl_in "%VS140COMNTOOLS%"
where cl.exe >nul 2>nul || (echo CL.exe not found & exit /b 1)
exit /b 0

:find_cl_in
if "%~1"=="" exit /b 1
if not exist "%~1\VsDevCmd.bat" exit /b 1
pushd .
call "%~1\VsDevCmd.bat" || exit /b 1
popd
exit /b 0

:find_cmake
if "%CMAKE_PATH%"=="" (echo CMAKE_PATH not set & exit /b 1)
set path=%PATH%;%CMAKE_PATH%
where cmake.exe >nul 2>nul || (echo CMAKE.exe not found & exit /b 1)
exit /b 0

:find_doxygen
if "%DOXYGEN_PATH%"=="" (echo DOXYGEN_PATH not set & exit /b 1)
set path=%PATH%;%DOXYGEN_PATH%
where doxygen.exe >nul 2>nul || (echo DOXYGEN.exe not found & exit /b 1)
exit /b 0
