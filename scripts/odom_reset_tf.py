#!/usr/bin/env python3
"""Bridge RViz 2D Pose Estimate to slam_toolbox.

RViz -> /initialpose_raw -> this node -> /initialpose (slam_toolbox)

Relays rf2o odometry as odom->base_link using scan timestamps (required by
slam_toolbox getOdomPose). Resets rf2o offset on each pose click.
Before first pose, publishes identity map->odom for RViz TF only.
"""
import math

import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped, TransformStamped
from nav_msgs.msg import Odometry
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_srvs.srv import Empty
from tf2_ros import TransformBroadcaster


def _yaw(q):
    siny = 2.0 * (q.w * q.z + q.x * q.y)
    cosy = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    return math.atan2(siny, cosy)


def _quat(yaw):
    return math.sin(yaw / 2.0), math.cos(yaw / 2.0)


class OdomResetTf(Node):
    def __init__(self):
        super().__init__('odom_reset_tf')
        self._tf = TransformBroadcaster(self)
        self._offset_x = 0.0
        self._offset_y = 0.0
        self._offset_yaw = 0.0
        self._last_rf2o = None
        self._pose_set = False

        self.create_subscription(Odometry, '/odom_rf2o', self._on_odom, 10)
        self.create_subscription(
            PoseWithCovarianceStamped, '/initialpose_raw', self._on_initial_pose, 10)
        self._slam_pose_pub = self.create_publisher(
            PoseWithCovarianceStamped, '/initialpose', 10)
        self._clear_buffer_cli = self.create_client(
            Empty, '/slam_toolbox/clear_localization_buffer')
        self.create_timer(0.05, self._on_timer)

        self.get_logger().info(
            '2D Pose Estimate: /initialpose_raw -> /initialpose; '
            'odom->base_link stamped from rf2o scans')

    def _publish_map_odom_identity(self):
        t = TransformStamped()
        t.header.stamp = self.get_clock().now().to_msg()
        t.header.frame_id = 'map'
        t.child_frame_id = 'odom'
        t.transform.rotation.w = 1.0
        self._tf.sendTransform(t)

    def _on_timer(self):
        if not self._pose_set:
            self._publish_map_odom_identity()

    def _publish_odom_tf(self, x, y, yaw, stamp):
        z, w = _quat(yaw)
        t = TransformStamped()
        t.header.stamp = stamp
        t.header.frame_id = 'odom'
        t.child_frame_id = 'base_link'
        t.transform.translation.x = x
        t.transform.translation.y = y
        t.transform.rotation.z = z
        t.transform.rotation.w = w
        self._tf.sendTransform(t)

    def _on_odom(self, msg):
        self._last_rf2o = msg
        x = msg.pose.pose.position.x - self._offset_x
        y = msg.pose.pose.position.y - self._offset_y
        yaw = _yaw(msg.pose.pose.orientation) - self._offset_yaw
        # slam_toolbox looks up odom->base_link at scan time — must match rf2o stamp.
        self._publish_odom_tf(x, y, yaw, msg.header.stamp)

    def _clear_localization_buffer(self):
        if self._clear_buffer_cli.service_is_ready():
            self._clear_buffer_cli.call_async(Empty.Request())

    def _on_initial_pose(self, msg):
        self._pose_set = True

        out = PoseWithCovarianceStamped()
        out.header.stamp = self.get_clock().now().to_msg()
        out.header.frame_id = 'map'
        out.pose = msg.pose
        self._slam_pose_pub.publish(out)
        self._clear_localization_buffer()

        if self._last_rf2o is not None:
            self._offset_x = self._last_rf2o.pose.pose.position.x
            self._offset_y = self._last_rf2o.pose.pose.position.y
            self._offset_yaw = _yaw(self._last_rf2o.pose.pose.orientation)
        else:
            self._offset_x = self._offset_y = self._offset_yaw = 0.0

        stamp = self.get_clock().now().to_msg()
        self._publish_odom_tf(0.0, 0.0, 0.0, stamp)

        yaw = _yaw(msg.pose.pose.orientation)
        self.get_logger().info(
            f'2D Pose: ({msg.pose.pose.position.x:.2f}, {msg.pose.pose.position.y:.2f}) '
            f'yaw={math.degrees(yaw):.1f}° — walk to localize')


def main():
    rclpy.init()
    node = OdomResetTf()
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
