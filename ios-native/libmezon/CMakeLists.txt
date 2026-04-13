cmake_minimum_required(VERSION 3.15)
project(MezonClient C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(BUILD_STATIC "Build as static library" ON)

set(SOURCES mezon_client.c)
set(HEADERS mezon_client.h)

add_definitions(-DNGTCP2_STATICLIB)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
)

if(BUILD_STATIC)
    add_library(mezon_client STATIC ${SOURCES})
else()
    add_library(mezon_client SHARED ${SOURCES})
endif()

if(UNIX AND NOT APPLE AND NOT ANDROID)
    message(STATUS "Configuring for Linux...")
    
    target_compile_options(mezon_client PRIVATE -O3 -Werror -Wall -fPIC)

    find_package(Threads REQUIRED)
    
    target_link_libraries(mezon_client 
        PRIVATE
        Threads::Threads
        dl
        m # Math library
    )

    target_link_libraries(mezon_client 
        PRIVATE
    )
endif()

if(MSVC)
    target_compile_options(mezon_client PRIVATE 
        /W4 /WX
        /wd5105 /wd4201 /wd4100
        /MD
        /O2 /Oi /Ot /GL
    )

    target_compile_definitions(mezon_client PRIVATE 
        WIN32_LEAN_AND_MEAN
        _CRT_SECURE_NO_WARNINGS
    )

    set_property(TARGET mezon_client PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)

    target_link_libraries(mezon_client PUBLIC 
        ws2_32
        advapi32
        ntdll
    )

    set_target_properties(mezon_client PROPERTIES 
        OUTPUT_NAME "mezon_client"
        PREFIX ""  # Removes 'lib' prefix on Windows (mezon_client.lib instead of libmezon_client.lib)
    )
endif()
    
if(APPLE)
    if(IOS)
        set_target_properties(mezon_client PROPERTIES
            MACOSX_BUNDLE_GUI_IDENTIFIER "com.mezon.client"
            XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "14.0"
        )
    endif()

elseif(ANDROID)
    find_library(LOG_LIB log)
    target_link_libraries(mezon_client PRIVATE ${LOG_LIB})
endif()

set_target_properties(mezon_client PROPERTIES 
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
)