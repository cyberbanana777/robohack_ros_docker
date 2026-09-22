# unitree_camera_driver

ROS 2 (rclcpp, C++) driver node for the Unitree USB/UVC stereo camera,
wrapping `UnitreeCameraSDK`. Publishes the left and right eye images as
separate `sensor_msgs/msg/Image` streams.

Written directly against `UnitreeCameraSDK.hpp` / `StereoCameraCommon.hpp`
(v1.1.0) — `UnitreeCamera(deviceNode)`, `startCapture()`,
`getStereoFrame(left, right, timestamp)`, `stopCapture()`.

## Topics published

| Topic                        | Type                    | Notes                     |
|-------------------------------|--------------------------|----------------------------|
| `/image_left/image_raw`       | `sensor_msgs/msg/Image` | `bgr8`, frame_id `<frame_id>_left`  |
| `/image_right/image_raw`      | `sensor_msgs/msg/Image` | `bgr8`, frame_id `<frame_id>_right` |

Publishing is skipped per-frame if a topic has no subscribers, so an idle
node doesn't spend CPU on encoding/copying — but the SDK capture thread and
`getStereoFrame()` polling loop always run.

## Parameters

See `config/params.yaml`:
- `device_node` (int, default `0`) — `/dev/video<N>`.
- `frame_width` / `frame_height` (int) — raw combined frame size; the SDK
  only supports `1856x800` or `928x400`.
- `fps` (double).
- `frame_id` (string) — topics use `<frame_id>_left` / `<frame_id>_right`.
- `config_file` (string) — path to a `stereo_camera_config.yaml` (as saved
  by `cam.saveConfig()`); if set, the node opens the camera from this file
  and `frame_width`/`frame_height`/`fps` are ignored.
- `sdk_log_level` (int) — forwarded to `UnitreeCamera::setLogLevel()`.

## Building

The SDK is a plain library, not a ROS/ament package, so `CMakeLists.txt`
locates it manually via a cache variable:

```bash
colcon build --packages-select unitree_camera_driver \
  --cmake-args -DUNITREE_CAMERA_SDK_DIR=/path/to/UnitreecameraSDK
```

Default lookup path is `/opt/UnitreecameraSDK`. If your base Docker image
already builds/installs the SDK there (as in the hackathon base image), you
can drop the `--cmake-args` override.

The lib subfolder (`lib/arm64` vs `lib/amd64`) is picked automatically from
`CMAKE_SYSTEM_PROCESSOR`, so this builds unmodified on the Jetson (aarch64)
and on an amd64 dev machine.

Build dependencies beyond the ROS packages in `package.xml`:
- OpenCV ≥ 4, built with GStreamer support (the SDK's internal
  `cv::VideoCapture` backend needs it) — already true for the
  `dustynv/ros:foxy-ros-base-l4t-r32.7.1` image.
- `libudev-dev` (linked by the SDK itself for USB device enumeration).

## Running

```bash
ros2 launch unitree_camera_driver unitree_camera.launch.py device_node:=0
```

or directly with a params file:

```bash
ros2 run unitree_camera_driver unitree_camera_node --ros-args --params-file config/params.yaml
```

## Notes / extension points

- USB permissions: the capturing user needs read/write access to
  `/dev/video<N>` (usually the `video` group) — add a udev rule or run in a
  privileged container if teams hit "camera failed to open".
- Only raw frames are published. If a team needs rectified images or a
  point cloud, `getRectStereoFrame()` / `startStereoCompute()` +
  `getPointCloud()` are available on the same `UnitreeCamera` object — wire
  them up as extra publishers the same way `captureLoop()` does for the raw
  frames.
- `getCalibParams()` can feed a `sensor_msgs/msg/CameraInfo` publisher if a
  team's pipeline needs intrinsics; left out here to keep the base driver
  minimal.
