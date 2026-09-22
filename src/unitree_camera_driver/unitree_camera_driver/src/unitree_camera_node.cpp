// unitree_camera_node.cpp
//
// ROS 2 driver node for the Unitree USB/UVC stereo camera (UnitreeCameraSDK).
// Captures frames on a dedicated thread (the SDK call is blocking) and
// publishes the left and right images as separate sensor_msgs/Image streams.

#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/header.hpp"
#include "sensor_msgs/msg/image.hpp"
#include "image_transport/image_transport.hpp"

#include <UnitreeCameraSDK.hpp>

using namespace std::chrono_literals;

namespace
{
// The SDK timestamps frames as microseconds since the Unix epoch.
rclcpp::Time toRosTime(const std::chrono::microseconds & stamp)
{
  const int64_t us = stamp.count();
  const int32_t sec = static_cast<int32_t>(us / 1000000);
  const uint32_t nsec = static_cast<uint32_t>((us % 1000000) * 1000);
  return rclcpp::Time(sec, nsec, RCL_ROS_TIME);
}

// Manual cv::Mat -> sensor_msgs::msg::Image conversion, in place of
// cv_bridge. cv_bridge pulls in whatever OpenCV it was itself built
// against (the system one) regardless of what this package links - mixing
// that with the vendor SDK's OpenCV 4.1.1 static libs risks an ABI
// mismatch. This only needs bgr8, tightly-packed rows, so it's a plain
// byte copy: no need for cv_bridge's more general encoding/conversion
// machinery at all.
sensor_msgs::msg::Image::SharedPtr matToImageMsg(
  const cv::Mat & frame, const rclcpp::Time & stamp, const std::string & frame_id)
{
  auto msg = std::make_shared<sensor_msgs::msg::Image>();
  msg->header.stamp = stamp;
  msg->header.frame_id = frame_id;
  msg->height = static_cast<uint32_t>(frame.rows);
  msg->width = static_cast<uint32_t>(frame.cols);
  msg->encoding = "bgr8";
  msg->is_bigendian = false;
  msg->step = static_cast<uint32_t>(frame.cols * frame.elemSize());

  const size_t size = static_cast<size_t>(msg->step) * frame.rows;
  msg->data.resize(size);

  if (frame.isContinuous()) {
    std::memcpy(msg->data.data(), frame.data, size);
  } else {
    // Row pitch in the source Mat can include padding; copy row by row.
    uint8_t * dst = msg->data.data();
    for (int r = 0; r < frame.rows; ++r) {
      std::memcpy(dst, frame.ptr(r), msg->step);
      dst += msg->step;
    }
  }
  return msg;
}
}  // namespace

class UnitreeCameraNode : public rclcpp::Node
{
public:
  UnitreeCameraNode()
  : Node("unitree_camera_node")
  {
    device_node_  = this->declare_parameter<int>("device_node", 0);
    frame_width_  = this->declare_parameter<int>("frame_width", 1856);
    frame_height_ = this->declare_parameter<int>("frame_height", 800);
    fps_          = this->declare_parameter<double>("fps", 30.0);
    frame_id_     = this->declare_parameter<std::string>("frame_id", "unitree_camera");
    config_file_  = this->declare_parameter<std::string>("config_file", "");
    sdk_log_level_ = this->declare_parameter<int>("sdk_log_level", 1);

    if (config_file_.empty()) {
      camera_ = std::make_unique<UnitreeCamera>(device_node_);
    } else {
      RCLCPP_INFO(get_logger(), "Loading camera config from '%s'", config_file_.c_str());
      camera_ = std::make_unique<UnitreeCamera>(config_file_);
    }

    if (!camera_->isOpened()) {
      RCLCPP_FATAL(get_logger(), "Failed to open Unitree camera on device node %d", device_node_);
      throw std::runtime_error("Unitree camera failed to open");
    }

    camera_->setLogLevel(sdk_log_level_);

    // A config file already carries frame size/rate; only apply the params
    // manually when we opened the camera by raw device node.
    if (config_file_.empty()) {
      camera_->setRawFrameSize(cv::Size(frame_width_, frame_height_));
      camera_->setRawFrameRate(static_cast<float>(fps_));
    }

    RCLCPP_INFO(get_logger(),
      "Opened Unitree camera (position #%d), frame size %dx%d @ %.1f fps",
      camera_->getPosNumber(), camera_->getRawFrameSize().width,
      camera_->getRawFrameSize().height, camera_->getRawFrameRate());

    if (!camera_->startCapture()) {
      RCLCPP_FATAL(get_logger(), "Failed to start camera capture thread");
      throw std::runtime_error("startCapture() failed");
    }

    const auto qos = rclcpp::SensorDataQoS().get_rmw_qos_profile();
    pub_left_  = image_transport::create_publisher(this, "image_left/image_raw", qos);
    pub_right_ = image_transport::create_publisher(this, "image_right/image_raw", qos);

    running_ = true;
    capture_thread_ = std::thread(&UnitreeCameraNode::captureLoop, this);
  }

  ~UnitreeCameraNode() override
  {
    running_ = false;
    if (capture_thread_.joinable()) {
      capture_thread_.join();
    }
    if (camera_) {
      camera_->stopCapture();
    }
  }

private:
  void captureLoop()
  {
    cv::Mat left, right;
    std::chrono::microseconds stamp;

    while (running_ && rclcpp::ok()) {
      if (!camera_->isOpened()) {
        RCLCPP_ERROR(get_logger(), "Camera reports closed, stopping capture loop");
        break;
      }

      // getStereoFrame() blocks briefly and returns false if no new frame
      // is ready yet; back off a touch and retry rather than busy-spinning.
      if (!camera_->getStereoFrame(left, right, stamp)) {
        std::this_thread::sleep_for(1ms);
        continue;
      }

      const rclcpp::Time ros_stamp = toRosTime(stamp);
      publishFrame(pub_left_, left, ros_stamp, frame_id_ + "_left");
      publishFrame(pub_right_, right, ros_stamp, frame_id_ + "_right");
    }
  }

  void publishFrame(
    image_transport::Publisher & pub, const cv::Mat & frame,
    const rclcpp::Time & stamp, const std::string & frame_id)
  {
    if (frame.empty() || pub.getNumSubscribers() == 0) {
      return;
    }
    const auto msg = matToImageMsg(frame, stamp, frame_id);
    pub.publish(*msg);
  }

  // Parameters
  int device_node_;
  int frame_width_;
  int frame_height_;
  double fps_;
  std::string frame_id_;
  std::string config_file_;
  int sdk_log_level_;

  std::unique_ptr<UnitreeCamera> camera_;
  image_transport::Publisher pub_left_;
  image_transport::Publisher pub_right_;

  std::thread capture_thread_;
  std::atomic<bool> running_{false};
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  int ret = 0;
  try {
    auto node = std::make_shared<UnitreeCameraNode>();
    rclcpp::spin(node);
  } catch (const std::exception & e) {
    RCLCPP_FATAL(rclcpp::get_logger("unitree_camera_node"), "%s", e.what());
    ret = 1;
  }
  rclcpp::shutdown();
  return ret;
}
