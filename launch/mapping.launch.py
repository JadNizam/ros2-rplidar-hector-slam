import math
import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, EmitEvent, OpaqueFunction, RegisterEventHandler
from launch.event_handlers import OnProcessExit
from launch.events import Shutdown
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

CONFIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'config')
RVIZ_CONFIG = os.path.join(os.path.dirname(__file__), '..', 'rviz', 'mapping.rviz')


def launch_setup(context, *args, **kwargs):
    min_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_min_deg')))
    max_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_max_deg')))
    offset = float(context.perform_substitution(LaunchConfiguration('angle_offset_deg')))
    lower_rad = math.radians(min_deg + offset)
    upper_rad = math.radians(max_deg + offset)

    # 1. RPLIDAR C1 driver — publishes /scan
    rplidar_node = Node(
        package='rplidar_ros',
        executable='rplidar_composition',
        name='rplidar',
        output='screen',
        parameters=[{
            'serial_port': '/dev/ttyUSB0',
            'serial_baudrate': 460800,
            'frame_id': 'laser',
            'angle_compensate': True,
        }],
    )

    # If rplidar exits, shut down launch so wrapper scripts can retry.
    rplidar_exit_handler = RegisterEventHandler(
        OnProcessExit(
            target_action=rplidar_node,
            on_exit=[EmitEvent(event=Shutdown())],
        )
    )

    return [
        rplidar_node,
        rplidar_exit_handler,

        # 2. Laser filter — range filter + front angular sector filter
        Node(
            package='laser_filters',
            executable='scan_to_scan_filter_chain',
            name='laser_filter',
            output='screen',
            parameters=[
                os.path.join(CONFIG_DIR, 'laser_filters.yaml'),
                {
                    'filter2.params.lower_angle': lower_rad,
                    'filter2.params.upper_angle': upper_rad,
                },
            ],
            remappings=[
                ('scan', '/scan'),
                ('scan_filtered', '/scan_filtered'),
            ],
        ),

        # 3. Static TFs
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='base_to_laser',
            arguments=[
                '--x', '0', '--y', '0', '--z', '0',
                '--roll', '0', '--pitch', '0', '--yaw', '0',
                '--frame-id', 'base_link', '--child-frame-id', 'laser',
            ],
        ),
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='odom_to_base',
            arguments=[
                '--x', '0', '--y', '0', '--z', '0',
                '--roll', '0', '--pitch', '0', '--yaw', '0',
                '--frame-id', 'odom', '--child-frame-id', 'base_link',
            ],
        ),

        # 4. SLAM Toolbox — consumes filtered scan
        Node(
            package='slam_toolbox',
            executable='async_slam_toolbox_node',
            name='slam_toolbox',
            output='screen',
            parameters=[
                os.path.join(CONFIG_DIR, 'slam_toolbox_lidar_only.yaml'),
                {'scan_topic': '/scan_filtered'},
            ],
        ),

        # 5. RViz
        Node(
            package='rviz2',
            executable='rviz2',
            name='rviz2',
            arguments=['-d', RVIZ_CONFIG],
            output='screen',
        ),
    ]


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'front_angle_min_deg',
            default_value='-150.0',
            description='Start of front sector in degrees (right side, negative = clockwise from forward)',
        ),
        DeclareLaunchArgument(
            'front_angle_max_deg',
            default_value='150.0',
            description='End of front sector in degrees (left side)',
        ),
        DeclareLaunchArgument(
            'angle_offset_deg',
            default_value='0.0',
            description='Rotational offset if LiDAR arrow does not align with scan angle 0',
        ),
        OpaqueFunction(function=launch_setup),
    ])
