# Arm Compiler 6 (armclang) toolchain for STM32F103C8T6.
#
# Why armclang instead of arm-none-eabi-gcc:
#   * It is the exact compiler Keil MDK ships, so the CMake build and the
#     UV4/MDK build compile identical code with identical semantics.
#   * It is already installed and licensed on a machine that runs MDK 5.
#   * CMake still emits compile_commands.json, which is what clangd / clang-tidy
#     / AI agents need for indexing.
#
# The link step is NOT done by CMake: Arm Compiler 6 links with armlink and a
# scatter file, so CMakeLists.txt drives armlink through a custom command.

cmake_minimum_required(VERSION 3.21)

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR cortex-m3)
# No license-free linker driver exists, so probe compilation only.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

if(NOT DEFINED ARMCLANG_ROOT)
  if(DEFINED ENV{ARMCLANG_ROOT})
    set(ARMCLANG_ROOT "$ENV{ARMCLANG_ROOT}")
  elseif(EXISTS "D:/Keil 5/ARM/ARMCLANG")
    set(ARMCLANG_ROOT "D:/Keil 5/ARM/ARMCLANG")
  elseif(EXISTS "C:/Keil_v5/ARM/ARMCLANG")
    set(ARMCLANG_ROOT "C:/Keil_v5/ARM/ARMCLANG")
  else()
    message(FATAL_ERROR
      "armclang not found. Set ARMCLANG_ROOT to the 'ARM/ARMCLANG' folder of your MDK install "
      "(contains bin/armclang.exe).")
  endif()
endif()

set(ARMCLANG_BIN "${ARMCLANG_ROOT}/bin")
set(CMAKE_C_COMPILER   "${ARMCLANG_BIN}/armclang.exe")
set(CMAKE_ASM_COMPILER "${ARMCLANG_BIN}/armclang.exe")
set(CMAKE_AR           "${ARMCLANG_BIN}/armar.exe")
set(CMAKE_OBJCOPY      "${ARMCLANG_BIN}/fromelf.exe")

set(MCU_FLAGS "-mcpu=cortex-m3 -mthumb")
set(CMAKE_C_FLAGS_INIT   "${MCU_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "${MCU_FLAGS} -masm=armasm")
set(CMAKE_EXECUTABLE_SUFFIX ".axf")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
