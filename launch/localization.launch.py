import os
import math
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

CONFIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'config')
RVIZ_CONFIG = os.path.join(os.path.dirname(__file__), '..', 'rviz', 'localization.rviz')


def launch_setup(context, *args, **kwargs):
    map_file  = context.perform_substitution(LaunchConfiguration('map_file'))
    min_deg   = float(context.perform_substitution(LaunchConfiguration('front_angle_min_deg')))
    max_deg   = float(context.perform_substitution(LaunchConfiguration('front_angle_max_deg')))
    offset    = float(context.perform_substitution(LaunchConfiguration('angle_offset_deg')))
    lower_rad = math.radians(min_deg + offset)
    upper_rad = math.radians(max_deg + offset)

    return [
        # 1. RPLIDAR C1 driver
        Node(
            package='rplidar_ros',
            executable='rplidar_composition',
            name='rplidar',
            output='screen',
            parameters=[{
                'serial_port': '/dev/ttyUSB0',
                'serial_baudrate': 460800,
                'frame_id': 'laser',
                'angle_compensate': True,
            }]
        ),

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
            remappings=[('scan', '/scan'), ('scan_filtered', '/scan_filtered')],
        ),

        # 3. Static TFs
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='base_to_laser',
            arguments=['--x', '0', '--y', '0', '--z', '0',
                       '--roll', '0', '--pitch', '0', '--yaw', '0',
                       '--frame-id', 'base_link', '--child-frame-id', 'laser'],
        ),
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='odom_to_base',
            arguments=['--x', '0', '--y', '0', '--z', '0',
                       '--roll', '0', '--pitch', '0', '--yaw', '0',
                       '--frame-id', 'odom', '--child-frame-id', 'base_link'],
        ),

        # 4. slam_toolbox in LOCALIZATION mode — loads existing map
        Node(
            package='slam_toolbox',
            executable='localization_slam_toolbox_node',
            name='slam_toolbox',
            output='screen',
            parameters=[
                os.path.join(CONFIG_DIR, 'slam_toolbox_localization.yaml'),
                {'map_file_name': map_file},
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
            'map_file',
            description='Path to slam_toolbox .posegraph map file (without extension)'
        ),
        DeclareLaunchArgument(
            'front_angle_min_deg', default_value='-90.0',
            description='Start of front sector in degrees'
        ),
        DeclareLaunchArgument(
            'front_angle_max_deg', default_value='90.0',
            description='End of front sector in degrees'
        ),
        DeclareLaunchArgument(
            'angle_offset_deg', default_value='0.0',
            description='Rotational offset if LiDAR arrow does not align with scan angle 0'
        ),
        OpaqueFunction(function=launch_setup),
    ])
