@echo off
rem Fritchii - compila en G:\Dev\build\release con clang-cl + Ninja (como las releases de Fritchii).
rem Uso: tools\arc\build.bat            (configura si hace falta y compila)
rem      tools\arc\build.bat reconfigure (fuerza la configuracion)
setlocal
rem VS 2026 (MSVC 14.51): el Qt incluido se compilo con esa STL; con VS 2022 falla el enlazado.
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=G:\BuildTools\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe;%PATH%"
set "VULKAN_SDK=C:\VulkanSDK\1.4.363.0"
set "SRC=G:\Dev\Fritchii"
set "OUT=G:\Dev\build\release"

if "%1"=="reconfigure" if exist "%OUT%\CMakeCache.txt" del "%OUT%\CMakeCache.txt"
if not exist "%OUT%\CMakeCache.txt" (
  cmake -S "%SRC%" -B "%OUT%" -G Ninja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER=G:/BuildTools/LLVM/bin/clang-cl.exe ^
    -DCMAKE_CXX_COMPILER=G:/BuildTools/LLVM/bin/clang-cl.exe ^
    -DCMAKE_LINKER=G:/BuildTools/LLVM/bin/lld-link.exe ^
    -DBUILD_TESTING=OFF -DYUZU_TESTS=OFF -DYUZU_CMD=OFF ^
    -DYUZU_ROOM=OFF -DYUZU_ROOM_STANDALONE=OFF ^
    -DYUZU_USE_BUNDLED_QT=ON -DYUZU_USE_BUNDLED_SDL3=ON -DYUZU_USE_BUNDLED_SIRIT=OFF ^
    -DENABLE_UPDATE_CHECKER=OFF -DUSE_DISCORD_PRESENCE=OFF ^
    -DLICHII_BUILD_TAG=arc-local -DLICHII_BUILD_PLATFORM=windows-x86_64 || exit /b 1
)
cmake --build "%OUT%" --target yuzu --parallel 12 || exit /b 1
echo BUILD OK
