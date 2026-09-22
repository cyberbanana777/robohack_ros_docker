cmake_minimum_required(VERSION 3.5)
project(unitree_camera_driver)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(std_msgs REQUIRED)
find_package(image_transport REQUIRED)
# ---------------------------------------------------------------------------
# Force a specific OpenCV build instead of whatever ament/ROS finds on the
# system. This must match the OpenCV the vendor UnitreeCameraSDK static libs
# were linked against, or you'll get ABI mismatches (segfaults) at runtime
# even though the build succeeds. Override with:
#   colcon build --cmake-args -DOPENCV_PREFIX=/path/to/opencv
#
# Deliberately NOT using cv_bridge here: cv_bridge's own Config.cmake runs
# find_package(OpenCV) internally (against whatever system OpenCV it was
# built with) and creates the opencv_core/opencv_imgproc/... imported
# targets first. A later find_package(OpenCV <version> EXACT) in this file
# can't redirect those same targets - most OpenCVConfig.cmake files guard
# target creation with if(NOT TARGET opencv_core), so the version check
# reports success while the targets themselves stay pointed at the system
# build. Converting cv::Mat -> sensor_msgs::msg::Image by hand below avoids
# pulling cv_bridge (and its system OpenCV) into the process at all.
# ---------------------------------------------------------------------------
set(OPENCV_PREFIX "/opt/opencv-4.1.1" CACHE PATH
    "Prefix of the OpenCV build to link against (must match the prebuilt UnitreeCameraSDK libs)")

# find_path() caches its result by default, which would otherwise "stick" to
# whatever was found (or not found) on the FIRST configure of this build
# directory and never get re-checked on later `colcon build` runs.
unset(_opencv_config_dir CACHE)
find_path(_opencv_config_dir OpenCVConfig.cmake
  PATHS ${OPENCV_PREFIX}
  PATH_SUFFIXES lib/cmake/opencv4 share/OpenCV lib/cmake/opencv share/opencv4 cmake
  NO_DEFAULT_PATH
  NO_CMAKE_ENVIRONMENT_PATH
  NO_SYSTEM_ENVIRONMENT_PATH
  NO_CMAKE_SYSTEM_PATH
)

if(NOT _opencv_config_dir)
  message(FATAL_ERROR
    "No OpenCVConfig.cmake found under '${OPENCV_PREFIX}' (checked "
    "lib/cmake/opencv4, share/OpenCV, lib/cmake/opencv, share/opencv4, cmake). "
    "Run: find ${OPENCV_PREFIX} -name OpenCVConfig.cmake -- and either add "
    "that subdirectory to PATH_SUFFIXES above, or build with "
    "-DOpenCV_DIR=<that directory> directly instead of -DOPENCV_PREFIX.")
endif()

unset(OpenCV_DIR CACHE)
set(OpenCV_DIR ${_opencv_config_dir} CACHE PATH "" FORCE)

# Only pull in the specific OpenCV modules we actually need. core/imgproc/
# videoio cover our own code; calib3d and highgui are pulled in purely
# because the vendor SDK's static lib references cv::StereoSGBM::create(),
# cv::StereoBM::create() and cv::waitKey() internally (from getPointCloud()/
# startStereoCompute(), which this node never calls) - as a static library,
# every symbol it defines must still resolve at link time even if unused.
# A custom OpenCV build (e.g. on Jetson) can list a module like opencv_gapi
# in its CMake config without having actually built it (ADE, gapi's
# dependency, failing to fetch during the OpenCV build is a common cause) -
# so we deliberately don't link the full OpenCV_LIBS list, only what's
# actually needed.
find_package(OpenCV 4.1.1 EXACT REQUIRED COMPONENTS core imgproc videoio calib3d highgui)
message(STATUS "unitree_camera_driver: using OpenCV ${OpenCV_VERSION} from ${OpenCV_DIR}")

find_package(Threads REQUIRED)

# ---------------------------------------------------------------------------
# Locate the vendor UnitreeCameraSDK. It is a plain CMake/Makefile library,
# not a ROS package, so we point at it manually. Override at build time with:
#   colcon build --cmake-args -DUNITREE_CAMERA_SDK_DIR=/path/to/UnitreecameraSDK
# ---------------------------------------------------------------------------
set(UNITREE_CAMERA_SDK_DIR "/opt/UnitreecameraSDK" CACHE PATH
    "Root directory of UnitreeCameraSDK (contains include/ and lib/)")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
  set(_unitree_sdk_arch "arm64")
else()
  set(_unitree_sdk_arch "amd64")
endif()

find_path(UNITREE_CAMERA_SDK_INCLUDE_DIR
  NAMES UnitreeCameraSDK.hpp
  PATHS ${UNITREE_CAMERA_SDK_DIR}/include
)

find_library(UNITREE_CAMERA_LIB unitree_camera
  PATHS ${UNITREE_CAMERA_SDK_DIR}/lib/${_unitree_sdk_arch})
find_library(UNITREE_V4L2_XU_LIB tstc_V4L2_xu_camera
  PATHS ${UNITREE_CAMERA_SDK_DIR}/lib/${_unitree_sdk_arch})
find_library(UNITREE_SYSTEMLOG_LIB systemlog
  PATHS ${UNITREE_CAMERA_SDK_DIR}/lib/${_unitree_sdk_arch})

if(NOT UNITREE_CAMERA_SDK_INCLUDE_DIR OR NOT UNITREE_CAMERA_LIB OR
   NOT UNITREE_V4L2_XU_LIB OR NOT UNITREE_SYSTEMLOG_LIB)
  message(FATAL_ERROR
    "UnitreeCameraSDK not found under '${UNITREE_CAMERA_SDK_DIR}' "
    "(arch: ${_unitree_sdk_arch}). Pass -DUNITREE_CAMERA_SDK_DIR=/path/to/UnitreecameraSDK "
    "or bake the SDK into the base image at that path.")
endif()

add_executable(unitree_camera_node src/unitree_camera_node.cpp)

# /opt/opencv-4.1.1/lib isn't on the system's default linker search path
# (no ldconfig entry, no LD_LIBRARY_PATH), so without an explicit RPATH the
# executable builds and links fine but fails at *launch* with "cannot open
# shared object file". Embed it directly in the binary - self-contained,
# no sudo/ldconfig/LD_LIBRARY_PATH juggling needed. Safe to do system-wide
# too if you'd rather: sonames differ (libopencv_core.so.4.1 vs the
# system's .so.4.5d), so they can't collide - but RPATH keeps this scoped
# to just this executable.
set_target_properties(unitree_camera_node PROPERTIES
  BUILD_RPATH "${OPENCV_PREFIX}/lib"
  INSTALL_RPATH "${OPENCV_PREFIX}/lib"
)

target_include_directories(unitree_camera_node PRIVATE
  ${UNITREE_CAMERA_SDK_INCLUDE_DIR}
  ${OpenCV_INCLUDE_DIRS}
)

ament_target_dependencies(unitree_camera_node
  rclcpp
  sensor_msgs
  std_msgs
  image_transport
)

target_link_libraries(unitree_camera_node
  ${UNITREE_CAMERA_LIB}
  ${UNITREE_V4L2_XU_LIB}
  ${UNITREE_SYSTEMLOG_LIB}
  udev
  ${OpenCV_LIBS}
  Threads::Threads
)

install(TARGETS unitree_camera_node
  DESTINATION lib/${PROJECT_NAME})

install(DIRECTORY launch config
  DESTINATION share/${PROJECT_NAME})

ament_package()
