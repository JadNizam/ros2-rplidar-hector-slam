import math
import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

CONFIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'config')
RVIZ_CONFIG = os.path.join(os.path.dirname(__file__), '..', 'rviz', 'mapping.rviz')


def launch_setup(context, *args, **kwargs):
    min_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_min_deg')))
    max_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_max_deg')))
    offset = float(context.perform_substitution(LaunchConfiguration('angle_offset_deg')))
    laser_yaw_deg = float(context.perform_substitution(LaunchConfiguration('laser_mount_yaw_deg')))
    lower_rad = math.radians(min_deg + offset)
    upper_rad = math.radians(max_deg + offset)
    laser_yaw_rad = math.radians(laser_yaw_deg)

    # RPLIDAR C1 driver — respawn on intermittent cold-start scan failures.
    rplidar_node = Node(
        package='rplidar_ros',
        executable='rplidar_composition',
        name='rplidar',
        output='screen',
        respawn=True,
        respawn_delay=3.0,
        parameters=[{
            'serial_port': '/dev/ttyUSB0',
            'serial_baudrate': 460800,
            'frame_id': 'laser',
            'angle_compensate': True,
        }],
    )

    return [
        rplidar_node,

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

        # 3. Static TF: base_link -> laser (handheld mounting yaw).
        # NOTE: odom -> base_link is NOT static anymore. It is published by
        # rf2o_laser_odometry below, which estimates real motion from the scans.
        # A static identity odom here is what made the handheld pose freeze:
        # slam_toolbox had no motion prior, so the scan matcher started every
        # match from "you didn't move" and under-registered translation,
        # ghosting smooth/curved walls.
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='base_to_laser',
            arguments=[
                '--x', '0', '--y', '0', '--z', '0',
                '--roll', '0', '--pitch', '0', '--yaw', str(laser_yaw_rad),
                '--frame-id', 'base_link', '--child-frame-id', 'laser',
            ],
        ),

        # 4. Laser odometry (rf2o) — estimates planar motion from consecutive
        # scans and publishes odom -> base_link. This is the motion prior that
        # lets slam_toolbox actually track the LiDAR as you walk (no wheels).
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
                # Empty => start odometry at the origin immediately (no GT topic
                # to wait for). Leaving the default makes rf2o hang forever.
                'init_pose_from_topic': '',
                'freq': 10.0,
            }],
        ),

        # 5. SLAM Toolbox — consumes filtered scan
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
            'front_angle_min_deg',
            default_value='-180.0',
            description='Start of kept sector in degrees. Default -180 = full 360 (best for room mapping). Narrow only if your body is unavoidably in view.',
        ),
        DeclareLaunchArgument(
            'front_angle_max_deg',
            default_value='180.0',
            description='End of kept sector in degrees. Default 180 = full 360.',
        ),
        DeclareLaunchArgument(
            'angle_offset_deg',
            default_value='0.0',
            description='Rotational offset if LiDAR arrow does not align with scan angle 0',
        ),
        DeclareLaunchArgument(
            'laser_mount_yaw_deg',
            default_value='-90.0',
            description='Yaw (deg) from base_link +X (RViz arrow) to laser frame. C1 handheld: -90 aligns the physical arrow with scan forward.',
        ),
        OpaqueFunction(function=launch_setup),
    ])
