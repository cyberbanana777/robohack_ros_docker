from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    args = [
        DeclareLaunchArgument('device_node', default_value='0'),
        DeclareLaunchArgument('frame_width', default_value='1856'),
        DeclareLaunchArgument('frame_height', default_value='800'),
        DeclareLaunchArgument('fps', default_value='30.0'),
        DeclareLaunchArgument('frame_id', default_value='unitree_camera'),
        DeclareLaunchArgument('config_file', default_value=''),
    ]

    node = Node(
        package='unitree_camera_driver',
        executable='unitree_camera_node',
        name='unitree_camera_node',
        output='screen',
        parameters=[{
            'device_node': LaunchConfiguration('device_node'),
            'frame_width': LaunchConfiguration('frame_width'),
            'frame_height': LaunchConfiguration('frame_height'),
            'fps': LaunchConfiguration('fps'),
            'frame_id': LaunchConfiguration('frame_id'),
            'config_file': LaunchConfiguration('config_file'),
        }],
    )

    return LaunchDescription(args + [node])
