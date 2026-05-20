import os
from launch import LaunchDescription
from launch.actions import ExecuteProcess, TimerAction, DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

CONFIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'config')
RVIZ_CONFIG = os.path.join(os.path.dirname(__file__), '..', 'rviz', 'mapping.rviz')


def generate_launch_description():
    map_file_arg = DeclareLaunchArgument(
        'map_file',
        description='Path to slam_toolbox .posegraph map file (without extension)'
    )
    map_file = LaunchConfiguration('map_file')

    return LaunchDescription([
        map_file_arg,

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

        # 2. Laser filter
        Node(
            package='laser_filters',
            executable='scan_to_scan_filter_chain',
            name='laser_filter',
            output='screen',
            parameters=[os.path.join(CONFIG_DIR, 'laser_filters.yaml')],
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

        # 6. Auto-lifecycle: configure at 4s, activate at 7s
        TimerAction(period=4.0, actions=[
            ExecuteProcess(
                cmd=['ros2', 'lifecycle', 'set', '/slam_toolbox', 'configure'],
                output='screen',
            )
        ]),
        TimerAction(period=7.0, actions=[
            ExecuteProcess(
                cmd=['ros2', 'lifecycle', 'set', '/slam_toolbox', 'activate'],
                output='screen',
            )
        ]),
    ])
