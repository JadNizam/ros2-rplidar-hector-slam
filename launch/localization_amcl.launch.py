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
from launch.events import matches_action
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import LifecycleNode, Node
from launch_ros.event_handlers import OnStateTransition
from launch_ros.events.lifecycle import ChangeState
from lifecycle_msgs.msg import Transition

CONFIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'config')
SCRIPT_DIR = os.path.join(os.path.dirname(__file__), '..', 'scripts')
RVIZ_CONFIG = os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', 'rviz', 'localization_amcl.rviz'))
MAPS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'maps'))


def launch_setup(context, *args, **kwargs):
    map_file = context.perform_substitution(LaunchConfiguration('map_file'))
    if not os.path.isabs(map_file):
        map_file = os.path.abspath(os.path.join(MAPS_DIR, map_file))
    map_yaml = map_file + '.yaml'

    min_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_min_deg')))
    max_deg = float(context.perform_substitution(LaunchConfiguration('front_angle_max_deg')))
    offset = float(context.perform_substitution(LaunchConfiguration('angle_offset_deg')))
    laser_yaw_deg = float(context.perform_substitution(LaunchConfiguration('laser_mount_yaw_deg')))
    node_delay = float(context.perform_substitution(LaunchConfiguration('node_start_delay_sec')))
    rviz_delay = float(context.perform_substitution(LaunchConfiguration('rviz_start_delay_sec')))
    lower_rad = math.radians(min_deg + offset)
    upper_rad = math.radians(max_deg + offset)
    laser_yaw_rad = math.radians(laser_yaw_deg)

    amcl_config = os.path.join(CONFIG_DIR, 'amcl.yaml')

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

    map_viz_node = Node(
        name='localization_map_viz',
        executable='python3',
        arguments=[os.path.join(SCRIPT_DIR, 'localization_map_viz.py'), map_yaml],
        output='screen',
    )

    amcl_node = LifecycleNode(
        package='nav2_amcl',
        executable='amcl',
        name='amcl',
        namespace='',
        output='screen',
        parameters=[amcl_config],
    )

    configure_amcl = EmitEvent(
        event=ChangeState(
            lifecycle_node_matcher=matches_action(amcl_node),
            transition_id=Transition.TRANSITION_CONFIGURE,
        )
    )
    activate_amcl = RegisterEventHandler(
        OnStateTransition(
            target_lifecycle_node=amcl_node,
            start_state='configuring',
            goal_state='inactive',
            entities=[
                LogInfo(msg='[localization_amcl] Activating amcl...'),
                EmitEvent(event=ChangeState(
                    lifecycle_node_matcher=matches_action(amcl_node),
                    transition_id=Transition.TRANSITION_ACTIVATE,
                )),
            ],
        )
    )

    delayed_nodes = [
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
    ]

    rviz_node = Node(
        package='rviz2',
        executable='rviz2',
        name='rviz2',
        arguments=['-d', RVIZ_CONFIG],
        output='screen',
    )

    rviz_after_map = TimerAction(
        period=rviz_delay,
        actions=[
            LogInfo(msg='[localization_amcl] Opening RViz (map on /map, particles on /particle_cloud)...'),
            rviz_node,
        ],
    )

    if node_delay > 0.0:
        delayed_nodes = [TimerAction(period=node_delay, actions=delayed_nodes)]

    return [
        map_viz_node,
        amcl_node,
        configure_amcl,
        activate_amcl,
        rplidar_node,
        rviz_after_map,
        *delayed_nodes,
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
            description='Yaw (deg) from base_link +X to laser frame. Must match mapping.',
        ),
        DeclareLaunchArgument(
            'node_start_delay_sec',
            default_value='1.0',
            description='Seconds before filter/odom nodes start (lets driver open serial first).',
        ),
        DeclareLaunchArgument(
            'rviz_start_delay_sec',
            default_value='3.0',
            description='Seconds before RViz opens.',
        ),
        OpaqueFunction(function=launch_setup),
    ])
