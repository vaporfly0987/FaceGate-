cmake_minimum_required(VERSION 3.24)
project(FaceGate VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(CTest)
add_library(facegate_core src/Gate.cpp)
target_include_directories(facegate_core PUBLIC include)
target_compile_options(facegate_core PRIVATE -Wall -Wextra -Wpedantic)
if(BUILD_TESTING)
  add_executable(gate_tests tests/GateTests.cpp)
  target_link_libraries(gate_tests PRIVATE facegate_core)
  add_test(NAME gate_tests COMMAND gate_tests)
endif()
if(NOT APPLE)
  message(STATUS "Building portable decision tests only; the application requires macOS")
  return()
endif()
enable_language(OBJCXX)
set(CMAKE_OBJCXX_STANDARD 17)
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")
endif()
find_package(OpenCV 4.8 REQUIRED COMPONENTS core imgproc objdetect dnn)
set(FACEGATE_MODELS "${CMAKE_SOURCE_DIR}/models" CACHE PATH "Verified ONNX model directory")
foreach(model face_detection_yunet_2023mar.onnx face_recognition_sface_2021dec.onnx)
  if(NOT EXISTS "${FACEGATE_MODELS}/${model}")
    message(FATAL_ERROR "Missing ${model}. Run python3 scripts/download_models.py")
  endif()
endforeach()
file(SHA256 "${FACEGATE_MODELS}/face_detection_yunet_2023mar.onnx" DETECTOR_HASH)
file(SHA256 "${FACEGATE_MODELS}/face_recognition_sface_2021dec.onnx" RECOGNIZER_HASH)
if(NOT DETECTOR_HASH STREQUAL "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4" OR
   NOT RECOGNIZER_HASH STREQUAL "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79")
  message(FATAL_ERROR "Model checksum mismatch")
endif()
add_library(facegate_vision src/Recognizer.cpp)
target_include_directories(facegate_vision PUBLIC include ${OpenCV_INCLUDE_DIRS})
target_link_libraries(facegate_vision PUBLIC ${OpenCV_LIBS} facegate_core)
add_executable(FaceGate MACOSX_BUNDLE src/App.mm src/MacSecurity.mm)
target_compile_options(FaceGate PRIVATE -fobjc-arc -Wall -Wextra)
target_link_libraries(FaceGate PRIVATE facegate_vision
  "-framework Cocoa" "-framework AVFoundation" "-framework CoreMedia"
  "-framework CoreVideo" "-framework Security" "-framework LocalAuthentication"
  "-framework ApplicationServices" "-framework OpenDirectory")
set_target_properties(FaceGate PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/packaging/Info.plist.in"
  MACOSX_BUNDLE_BUNDLE_NAME FaceGate
  MACOSX_BUNDLE_GUI_IDENTIFIER org.facegate.FaceGate
  MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
  MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION})
add_custom_command(TARGET FaceGate POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:FaceGate>/Resources"
  COMMAND ${CMAKE_COMMAND} -E copy
    "${FACEGATE_MODELS}/face_detection_yunet_2023mar.onnx"
    "${FACEGATE_MODELS}/face_recognition_sface_2021dec.onnx"
    "$<TARGET_BUNDLE_CONTENT_DIR:FaceGate>/Resources"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_SOURCE_DIR}/licenses"
    "$<TARGET_BUNDLE_CONTENT_DIR:FaceGate>/Resources/licenses"
  COMMAND /usr/bin/codesign --force --sign - --identifier org.facegate.FaceGate
    "$<TARGET_BUNDLE_DIR:FaceGate>"
  VERBATIM)
if(BUILD_TESTING)
  add_executable(vision_smoke tests/VisionSmoke.cpp)
  target_link_libraries(vision_smoke PRIVATE facegate_vision)
  add_test(NAME vision_smoke COMMAND vision_smoke "${FACEGATE_MODELS}")
endif()
install(TARGETS FaceGate BUNDLE DESTINATION libexec)
