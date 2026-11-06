cmake_minimum_required(VERSION 3.21)

# Must be set BEFORE project(): CMake's ARMClang module reads it while detecting
# the compiler and otherwise injects a broken "-march=" derived from
# CMAKE_SYSTEM_PROCESSOR. The toolchain file owns -mcpu instead.
if(POLICY CMP0123)
  cmake_policy(SET CMP0123 NEW)
endif()

# ---------------------------------------------------------------------------
# STM32F103C8T6 application - build driven by Arm Compiler 6 (armclang/armlink)
#
#   cmake --preset Debug
#   cmake --build --preset Debug
#
# Outputs in <build>/ : firmware.axf / firmware.hex / firmware.bin / firmware.map
# ---------------------------------------------------------------------------
project(stm32f103c8_app C)

if(NOT CMAKE_TOOLCHAIN_FILE)
  message(FATAL_ERROR "Configure with -DCMAKE_TOOLCHAIN_FILE=cmake/armclang-toolchain.cmake (use the CMake presets).")
endif()

set(MCU_NAME "STM32F103C8Tx")
set(MCU_DEFINE "STM32F103xB")

# --- Firmware package (STM32CubeF1) ---------------------------------------
if(NOT STM32CUBE_F1_ROOT)
  if(DEFINED ENV{STM32CUBE_F1_ROOT})
    set(STM32CUBE_F1_ROOT "$ENV{STM32CUBE_F1_ROOT}")
  else()
    set(STM32CUBE_F1_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/external/cubeF1/STM32CubeF1-master")
  endif()
endif()
if(NOT EXISTS "${STM32CUBE_F1_ROOT}/Drivers/CMSIS/Device/ST/STM32F1xx/Include/stm32f1xx.h")
  message(FATAL_ERROR
    "STM32CubeF1 not found at '${STM32CUBE_F1_ROOT}'.\n"
    "Run:  powershell -ExecutionPolicy Bypass -File tools/setup.ps1\n"
    "or point STM32CUBE_F1_ROOT at an existing STM32Cube_FW_F1 package.")
endif()

set(CMSIS_CORE_INC   "${STM32CUBE_F1_ROOT}/Drivers/CMSIS/Core/Include")
set(CMSIS_DEVICE_DIR "${STM32CUBE_F1_ROOT}/Drivers/CMSIS/Device/ST/STM32F1xx")
set(HAL_DIR          "${STM32CUBE_F1_ROOT}/Drivers/STM32F1xx_HAL_Driver")

# --- Application sources ---------------------------------------------------
# Everything under App/ and Bsp/ is written by humans and AI agents.
# Core/ is the CubeMX-shaped entry layer. Drivers/ (HAL) is read-only.
set(APP_SOURCES
  App/Src/app.c
  App/Src/ringbuffer.c
  Bsp/Src/bsp_board.c
  Bsp/Src/bsp_log.c
  Bsp/Src/bsp_fault.c
  Core/Src/main.c
  Core/Src/stm32f1xx_it.c
)

# Only the HAL modules this project actually uses. Add a line when a driver
# needs a new peripheral - the AI is expected to extend this list, not to
# compile the whole HAL.
set(HAL_SOURCES
  ${HAL_DIR}/Src/stm32f1xx_hal.c
  ${HAL_DIR}/Src/stm32f1xx_hal_cortex.c
  ${HAL_DIR}/Src/stm32f1xx_hal_dma.c
  ${HAL_DIR}/Src/stm32f1xx_hal_exti.c
  ${HAL_DIR}/Src/stm32f1xx_hal_flash.c
  ${HAL_DIR}/Src/stm32f1xx_hal_flash_ex.c
  ${HAL_DIR}/Src/stm32f1xx_hal_gpio.c
  ${HAL_DIR}/Src/stm32f1xx_hal_pwr.c
  ${HAL_DIR}/Src/stm32f1xx_hal_rcc.c
  ${HAL_DIR}/Src/stm32f1xx_hal_rcc_ex.c
  ${HAL_DIR}/Src/stm32f1xx_hal_uart.c
)

add_library(fw_obj OBJECT
  ${APP_SOURCES}
  ${HAL_SOURCES}
  ${CMSIS_DEVICE_DIR}/Source/Templates/system_stm32f1xx.c
)

target_include_directories(fw_obj PRIVATE
  Core/Include
  App/Include
  Bsp/Include
  ${CMSIS_CORE_INC}
  ${CMSIS_DEVICE_DIR}/Include
  ${HAL_DIR}/Inc
)

target_compile_definitions(fw_obj PRIVATE
  ${MCU_DEFINE}
  USE_HAL_DRIVER
)

target_compile_options(fw_obj PRIVATE
  -std=c99
  -ffunction-sections
  -fdata-sections
  -fno-common
  -Wall
  -Wextra
  -Wno-unused-parameter
)

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  target_compile_options(fw_obj PRIVATE -O2)
else()
  target_compile_options(fw_obj PRIVATE -O0 -g3)
endif()

# --- Startup (ARM-syntax assembler, compiled outside CMake's language rules) ---
set(STARTUP_S "${CMSIS_DEVICE_DIR}/Source/Templates/arm/startup_stm32f103xb.s")
set(STARTUP_O "${CMAKE_BINARY_DIR}/startup_stm32f103xb.o")

add_custom_command(
  OUTPUT  ${STARTUP_O}
  COMMAND ${CMAKE_C_COMPILER} --target=arm-arm-none-eabi -mcpu=cortex-m3 -mthumb
          -masm=armasm -c ${STARTUP_S} -o ${STARTUP_O}
  DEPENDS ${STARTUP_S}
  COMMENT "armclang: startup_stm32f103xb.s"
  VERBATIM
)

# --- Link (armlink + scatter file) -----------------------------------------
set(AXF  "${CMAKE_BINARY_DIR}/firmware.axf")
set(BIN  "${CMAKE_BINARY_DIR}/firmware.bin")
set(HEX  "${CMAKE_BINARY_DIR}/firmware.hex")
# armlink's --map prints to stdout (it is captured in build.log by
# tools/build.ps1); these two text files are the machine-readable artifacts.
set(SIZES  "${CMAKE_BINARY_DIR}/firmware_sizes.txt")
set(SYMBOLS "${CMAKE_BINARY_DIR}/firmware_symbols.txt")

add_custom_command(
  OUTPUT  ${AXF} ${BIN} ${HEX} ${SIZES} ${SYMBOLS}
  COMMAND ${ARMCLANG_BIN}/armlink.exe
            --cpu=Cortex-M3
            --scatter=${CMAKE_CURRENT_SOURCE_DIR}/cmake/stm32f103c8tx.sct
            --map
            --datacompressor=off
            --info=sizes,totals
            --summary_stderr
            -o ${AXF}
            $<TARGET_OBJECTS:fw_obj>
            ${STARTUP_O}
  COMMAND ${ARMCLANG_BIN}/fromelf.exe --i32combined --output ${HEX} ${AXF}
  COMMAND ${ARMCLANG_BIN}/fromelf.exe --bin --output ${BIN} ${AXF}
  COMMAND ${ARMCLANG_BIN}/fromelf.exe --text -z --output ${SIZES} ${AXF}
  COMMAND ${ARMCLANG_BIN}/fromelf.exe --text -s --output ${SYMBOLS} ${AXF}
  DEPENDS fw_obj ${STARTUP_O}
  COMMENT "armlink: firmware.axf"
  COMMAND_EXPAND_LISTS
  VERBATIM
)

add_custom_target(firmware ALL DEPENDS ${AXF})
