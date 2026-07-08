#!/usr/bin/env python3
"""Forward RViz 2D Pose Estimate to slam_toolbox and clear localization buffer.

RViz -> /initialpose_raw -> this node -> /initialpose (slam_toolbox)
"""
import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_srvs.srv import Empty


class InitialPoseRelay(Node):
    def __init__(self):
        super().__init__('initial_pose_relay')

        self.create_subscription(
            PoseWithCovarianceStamped, '/initialpose_raw', self._on_initial_pose, 10)
        self._slam_pose_pub = self.create_publisher(
            PoseWithCovarianceStamped, '/initialpose', 10)
        self._clear_buffer_cli = self.create_client(
            Empty, '/slam_toolbox/clear_localization_buffer')

        self.get_logger().info('2D Pose Estimate: /initialpose_raw -> /initialpose')

    def _clear_localization_buffer(self):
        if self._clear_buffer_cli.service_is_ready():
            self._clear_buffer_cli.call_async(Empty.Request())

    def _on_initial_pose(self, msg):
        out = PoseWithCovarianceStamped()
        out.header.stamp = self.get_clock().now().to_msg()
        out.header.frame_id = 'map'
        out.pose = msg.pose
        self._slam_pose_pub.publish(out)
        self._clear_localization_buffer()

        p = msg.pose.pose.position
        self.get_logger().info(
            f'2D Pose: ({p.x:.2f}, {p.y:.2f}) — stand still ~2s, then walk')


def main():
    rclpy.init()
    node = InitialPoseRelay()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
