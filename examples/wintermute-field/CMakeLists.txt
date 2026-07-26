cmake_minimum_required(VERSION 3.20)
project(wintermute_field C CUDA CXX)

find_package(CUDAToolkit REQUIRED)

# ── the CLI: render / bench / verify ──────────────────────────────────────
add_executable(wintermute-field field.cu)
set_target_properties(wintermute-field PROPERTIES
  CUDA_STANDARD 20
  CXX_STANDARD 20
)
install(TARGETS wintermute-field RUNTIME DESTINATION bin)

# ── the wayland presenter daemon (optional: needs wayland + protocol xmls) ─
find_package(PkgConfig)
if(PkgConfig_FOUND)
  pkg_check_modules(WAYLAND wayland-client)
endif()

if(NOT WAYLAND_SCANNER)
  find_program(WAYLAND_SCANNER wayland-scanner)
endif()

if(WAYLAND_FOUND AND WAYLAND_SCANNER AND WLR_LAYER_SHELL_XML AND XDG_SHELL_XML)
  set(GEN ${CMAKE_CURRENT_BINARY_DIR}/protocols)
  file(MAKE_DIRECTORY ${GEN})

  add_custom_command(
    OUTPUT ${GEN}/wlr-layer-shell-unstable-v1-client-protocol.h
    COMMAND ${WAYLAND_SCANNER} client-header ${WLR_LAYER_SHELL_XML}
            ${GEN}/wlr-layer-shell-unstable-v1-client-protocol.h)
  add_custom_command(
    OUTPUT ${GEN}/wlr-layer-shell-protocol.c
    COMMAND ${WAYLAND_SCANNER} private-code ${WLR_LAYER_SHELL_XML}
            ${GEN}/wlr-layer-shell-protocol.c)
  add_custom_command(
    OUTPUT ${GEN}/xdg-shell-client-protocol.h
    COMMAND ${WAYLAND_SCANNER} client-header ${XDG_SHELL_XML}
            ${GEN}/xdg-shell-client-protocol.h)
  add_custom_command(
    OUTPUT ${GEN}/xdg-shell-protocol.c
    COMMAND ${WAYLAND_SCANNER} private-code ${XDG_SHELL_XML}
            ${GEN}/xdg-shell-protocol.c)

  add_executable(wintermute-field-daemon
    presenter.cu
    ${GEN}/wlr-layer-shell-protocol.c
    ${GEN}/xdg-shell-protocol.c
    ${GEN}/wlr-layer-shell-unstable-v1-client-protocol.h
    ${GEN}/xdg-shell-client-protocol.h)
  set_target_properties(wintermute-field-daemon PROPERTIES
    CUDA_STANDARD 20
    CXX_STANDARD 20
  )
  target_include_directories(wintermute-field-daemon PRIVATE ${GEN} ${WAYLAND_INCLUDE_DIRS})
  target_link_libraries(wintermute-field-daemon PRIVATE ${WAYLAND_LIBRARIES})
  install(TARGETS wintermute-field-daemon RUNTIME DESTINATION bin)
else()
  message(STATUS "wayland/scanner/protocol xmls not provided — CLI only")
endif()
