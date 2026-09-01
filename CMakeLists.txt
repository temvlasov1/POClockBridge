cmake_minimum_required(VERSION 3.16)
project(POClockBridgeCore VERSION 0.4.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(poclock_core STATIC Core/POClockEngine.cpp)
target_include_directories(poclock_core PUBLIC Core)

if(MSVC)
    target_compile_options(poclock_core PRIVATE /W4 /permissive-)
else()
    target_compile_options(poclock_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

add_executable(poclock_tests Tests/test_engine.cpp)
target_link_libraries(poclock_tests PRIVATE poclock_core)
if(MSVC)
    target_compile_options(poclock_tests PRIVATE /W4 /permissive-)
else()
    target_compile_options(poclock_tests PRIVATE -Wall -Wextra -Wpedantic)
endif()

enable_testing()
add_test(NAME poclock_core_tests COMMAND poclock_tests)
