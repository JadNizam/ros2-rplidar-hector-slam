import math
import os

from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    EmitEvent,
    LogInfo,
    OpaqueFunction,
    RegisterEventHandler,
    TimerAction,
)
from launch.event_handlers import OnProcessExit
from launch.events import Shutdown, matches_action
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import LifecycleNode, Node
from launch_ros.event_handlers import OnStateTransition
from launch_ros.events.lifecycle import ChangeState
from lifecycle_msgs.msg import Transition

CONFIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'config')
RVIZ_CONFIG = os.path.join(os.path.dirname(__file__), '..', 'rviz', 'localization.rviz')
MAPS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'maps'))


def launch_setup(context, *args, **kwargs):
    map_file = context.perform_substitution(LaunchConfiguration('map_file'))
    if not os.path.isabs(map_file):
        map_file = os.path.abspath(os.path.join(MAPS_DIR, map_file))

    min_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_min_deg')))
    max_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_max_deg')))
    offset = float(context.perform_substitution(LaunchConfiguration('angle_offset_deg')))
    laser_yaw_deg = float(context.perform_substitution(LaunchConfiguration('laser_mount_yaw_deg')))
    node_delay = float(context.perform_substitution(LaunchConfiguration('node_start_delay_sec')))
    slam_delay = float(context.perform_substitution(LaunchConfiguration('slam_start_delay_sec')))
    lower_rad = math.radians(min_deg + offset)
    upper_rad = math.radians(max_deg + offset)
    laser_yaw_rad = math.radians(laser_yaw_deg)

    # LiDAR starts immediately and owns /dev/ttyUSB0 before anything else touches ROS I/O.
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

    rplidar_exit_handler = RegisterEventHandler(
        OnProcessExit(
            target_action=rplidar_node,
            on_exit=[EmitEvent(event=Shutdown())],
        )
    )

    slam_toolbox_node = LifecycleNode(
        package='slam_toolbox',
        executable='localization_slam_toolbox_node',
        name='slam_toolbox',
        namespace='',
        output='screen',
        parameters=[
            os.path.join(CONFIG_DIR, 'slam_toolbox_localization.yaml'),
            {'map_file_name': map_file, 'use_sim_time': False},
        ],
    )

    configure_slam = EmitEvent(
        event=ChangeState(
            lifecycle_node_matcher=matches_action(slam_toolbox_node),
            transition_id=Transition.TRANSITION_CONFIGURE,
        )
    )
    activate_slam = RegisterEventHandler(
        OnStateTransition(
            target_lifecycle_node=slam_toolbox_node,
            start_state='configuring',
            goal_state='inactive',
            entities=[
                LogInfo(msg='[localization] Activating slam_toolbox...'),
                EmitEvent(
                    event=ChangeState(
                        lifecycle_node_matcher=matches_action(slam_toolbox_node),
                        transition_id=Transition.TRANSITION_ACTIVATE,
                    )
                ),
            ],
        )
    )

    support_nodes = [
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
        Node(
            package='rviz2',
            executable='rviz2',
            name='rviz2',
            arguments=['-d', RVIZ_CONFIG],
            output='screen',
        ),
    ]

    slam_actions = [slam_toolbox_node, configure_slam, activate_slam]
    if slam_delay > 0.0:
        slam_actions = [TimerAction(period=node_delay + slam_delay, actions=slam_actions)]

    if node_delay > 0.0:
        support_nodes = [TimerAction(period=node_delay, actions=support_nodes)]

    return [
        rplidar_node,
        rplidar_exit_handler,
        *support_nodes,
        *slam_actions,
    ]


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'map_file',
            default_value=os.path.join(MAPS_DIR, 'my_room'),
            description='Absolute path to map base name (no extension)',
        ),
        DeclareLaunchArgument('front_angle_min_deg', default_value='-180.0'),
        DeclareLaunchArgument('front_angle_max_deg', default_value='180.0'),
        DeclareLaunchArgument('angle_offset_deg', default_value='0.0'),
        DeclareLaunchArgument(
            'laser_mount_yaw_deg',
            default_value='-90.0',
            description='Yaw (deg) from base_link +X (RViz arrow) to laser frame. Must match mapping.',
        ),
        DeclareLaunchArgument(
            'node_start_delay_sec',
            default_value='1.0',
            description='Seconds before non-LiDAR nodes start (lets driver open serial first).',
        ),
        DeclareLaunchArgument(
            'slam_start_delay_sec',
            default_value='3.0',
            description='Extra seconds before slam_toolbox after node_start_delay_sec.',
        ),
        OpaqueFunction(function=launch_setup),
    ])
