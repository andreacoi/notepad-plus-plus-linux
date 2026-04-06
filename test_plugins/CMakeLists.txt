cmake_minimum_required(VERSION 3.20)
project(test_plugins LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)

add_executable(test_plugins test_plugins.mm)
target_link_libraries(test_plugins PRIVATE "-framework Foundation")
