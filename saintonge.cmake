# Variables required: $ENV{SGE_TOOLS}

# Windows build helpers: Set a variable based on 32 or 64 bit
function(set_3264 Variable value32 value64)
  if("${CMAKE_GENERATOR}" MATCHES "Win64")
    set(${Variable} ${value64} PARENT_SCOPE)
  else()
    set(${Variable} ${value32} PARENT_SCOPE)
  endif()
endfunction(set_3264)

# target_enable_pch: turn on PCH for a VS project
# Assumes SGE_TOOLS is set to the build folder
function(target_enable_pch Target Pch)
  if(MSVC)
    configure_file("$ENV{SGE_TOOLS}/stdafx.cpp.in" stdafx.cpp)
    set_target_properties(${Target} PROPERTIES COMPILE_FLAGS "/Yu${Pch}")
    target_sources(${Target} PRIVATE stdafx.cpp)
    set_source_files_properties(stdafx.cpp PROPERTIES COMPILE_FLAGS "/Yc${Pch}")
  endif(MSVC)
endfunction(target_enable_pch)

# Windows basics: Define Unicode, stdcall by default
function(target_set_windows_baseline Target)
  if(MSVC)
    target_compile_definitions(${Target} PUBLIC -DUNICODE -D_UNICODE)
    if(NOT "${CMAKE_GENERATOR}" MATCHES "Win64")
      target_compile_options(${Target} /Gz)
    endif()
  endif(MSVC)
endfunction(target_set_windows_baseline)

# MIDL support
function(add_midl_target MidlTargetName IdlFiles)
  set_3264(WINDOWS_BUILD_ARCH "win32" "x64")
  set_3264(WINDOWS_BUILD_ARCH_MIDL_DEFINES "/Di386 /D_X86_" "/D_AMD64_ /D_WIN64")

  MESSAGE(STATUS "Generating MIDL Target: " ${MidlTargetName})
  LIST(APPEND MidlGeneratedOutput
    ${CMAKE_CURRENT_BINARY_DIR}/dlldata.c
  )

  get_property(dirs DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY INCLUDE_DIRECTORIES)
  foreach(includedir ${dirs})
    list(APPEND myMidlIncludes /I ${includedir})
  endforeach()

  foreach(idlFile IN LISTS IdlFiles)
    get_filename_component(idlFileName ${idlFile} NAME)
    MESSAGE(STATUS "  IDL File: " ${idlFileName})
    string(REGEX REPLACE "\\.[^.]*$" "" idlBase ${idlFileName})
    LIST(APPEND MidlGeneratedOutput
      ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}.h
      ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}_p.c
      ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}_i.c
      ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}.tlb
    )

    get_filename_component(fullIdlFile ${idlFile} ABSOLUTE)
    add_custom_command(
      OUTPUT
        ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}.h
        ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}_p.c
        ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}_i.c
        ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}.tlb
        ${CMAKE_CURRENT_BINARY_DIR}/dlldata.c
        COMMAND midl.exe /Zp8 /char unsigned /ms_ext /c_ext /header ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}.h /proxy ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}_p.c /dlldata ${CMAKE_CURRENT_BINARY_DIR}/dlldata.c /iid ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}_i.c /tlb ${CMAKE_CURRENT_BINARY_DIR}/${idlBase}.tlb -D_MERGE_PROXYSTUB -D_ARM_WINAPI_PARTITION_DESKTOP_SDK_AVAILABLE /D_USE_DEV11_CRT -D_APISET_WINDOWS_VERSION=0x601 -D_APISET_MINWIN_VERSION=0x0107 -D_APISET_MINCORE_VERSION=0x0106 /DMSC_NOOPT /DNTDDI_VERSION=0x0A000003 /DWINBLUE_KBSPRING14 /DBUILD_WINDOWS /D__WRL_CONFIGURATION_LEGACY__ /DBUILD_UMS_ENABLED=0 /DBUILD_WOW64_ENABLED=0 -D_USE_DECLSPECS_FOR_SAL=1 /DRUN_WPP -D_CONTROL_FLOW_GUARD=1 -D_CONTROL_FLOW_GUARD_SVCTAB=1 /D_WCHAR_T_DEFINED ${WINDOWS_BUILD_ARCH_MIDL_DEFINES} /no_stamp /nologo /WX /no_settings_comment ${myMidlIncludes} /lcid 1033 -sal /env ${WINDOWS_BUILD_ARCH} -target NT100 ${fullIdlFile}
      WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
      DEPENDS ${idlFile}
      VERBATIM
    )
  endforeach(idlFile)

  add_custom_target(${MidlTargetName}
    DEPENDS
      ${MidlGeneratedOutput}
  )

  MESSAGE(STATUS "Output: " "${MidlGeneratedOutput}")
  set_source_files_properties(
    ${MidlGeneratedOutput}
      PROPERTIES
        GENERATED TRUE
  )
endfunction(add_midl_target)

function(add_com_interop_dll TargetName TlbFile)
  set_3264(DOTNET_BUILD_ARCH "X86" "X64")
  get_filename_component(tlbFileName ${TlbFile} NAME)
  string(REGEX REPLACE "\\.[^.]*$" "" tlbBase ${tlbFileName})

  get_filename_component(fullTlbFile ${TlbFile} ABSOLUTE)
  set(OutputDll "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_CFG_INTDIR}/${tlbBase}.Interop.${DOTNET_BUILD_ARCH}.dll")

  add_custom_command(
    OUTPUT ${OutputDll}
    COMMAND tlbimp /machine:${DOTNET_BUILD_ARCH} ${fullTlbFile} /out:${OutputDll}
    DEPENDS ${TlbFile}
  )

  add_custom_target(
    ${TargetName} ALL
    DEPENDS ${OutputDll}
  )
endfunction(add_com_interop_dll)
