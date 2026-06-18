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

        # 3. Static TF: base_link -> laser. (odom -> base_link comes from rf2o.)
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='base_to_laser',
            arguments=['--x', '0', '--y', '0', '--z', '0',
                       '--roll', '0', '--pitch', '0', '--yaw', '0',
                       '--frame-id', 'base_link', '--child-frame-id', 'laser'],
        ),

        # 4. Laser odometry (rf2o) — odom -> base_link motion prior from scans.
        Node(
            package='rf2o_laser_odometry',
            executable='rf2o_laser_odometry_node',
            name='rf2o_laser_odometry',
            output='screen',
            parameters=[{
                'laser_scan_topic': '/scan_filtered',
                'odom_topic': '/odom_rf2o',
                'publish_tf': True,
                'base_frame_id': 'base_link',
                'odom_frame_id': 'odom',
                'init_pose_from_topic': '',
                'freq': 10.0,
            }],
        ),

        # 5. slam_toolbox in LOCALIZATION mode — loads existing map
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

        # 6. RViz
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
            'front_angle_min_deg', default_value='-180.0',
            description='Start of kept sector in degrees. Default -180 = full 360.'
        ),
        DeclareLaunchArgument(
            'front_angle_max_deg', default_value='180.0',
            description='End of kept sector in degrees. Default 180 = full 360.'
        ),
        DeclareLaunchArgument(
            'angle_offset_deg', default_value='0.0',
            description='Rotational offset if LiDAR arrow does not align with scan angle 0'
        ),
        OpaqueFunction(function=launch_setup),
    ])
