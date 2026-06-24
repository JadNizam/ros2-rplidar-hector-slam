#!/usr/bin/env python3
"""Bridge RViz 2D Pose Estimate to slam_toolbox without touching map TF.

RViz -> /initialpose_raw -> this node -> /initialpose (slam_toolbox)

Only resets rf2o odometry offset and odom->base_link at click time.
slam_toolbox keeps sole ownership of map->odom; launch provides bootstrap map->odom.
"""
import math

import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped, TransformStamped
from nav_msgs.msg import Odometry
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from tf2_ros import TransformBroadcaster


def _yaw(q):
    siny = 2.0 * (q.w * q.z + q.x * q.y)
    cosy = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    return math.atan2(siny, cosy)


class OdomResetTf(Node):
    def __init__(self):
        super().__init__('odom_reset_tf')
        self._tf = TransformBroadcaster(self)
        self._offset_x = 0.0
        self._offset_y = 0.0
        self._offset_yaw = 0.0
        self._last_rf2o = None

        self.create_subscription(Odometry, '/odom_rf2o', self._on_odom, 10)
        self.create_subscription(
            PoseWithCovarianceStamped, '/initialpose_raw', self._on_initial_pose, 10)
        self._slam_pose_pub = self.create_publisher(
            PoseWithCovarianceStamped, '/initialpose', 10)
        self.create_timer(0.05, self._publish_identity_until_rf2o)

        self.get_logger().info(
            '2D Pose Estimate: /initialpose_raw -> /initialpose (map TF untouched)')

    def _publish_tf(self, x, y, yaw):
        t = TransformStamped()
        t.header.stamp = self.get_clock().now().to_msg()
        t.header.frame_id = 'odom'
        t.child_frame_id = 'base_link'
        t.transform.translation.x = x
        t.transform.translation.y = y
        t.transform.rotation.z = math.sin(yaw / 2.0)
        t.transform.rotation.w = math.cos(yaw / 2.0)
        self._tf.sendTransform(t)

    def _publish_identity_until_rf2o(self):
        if self._last_rf2o is None:
            self._publish_tf(0.0, 0.0, 0.0)

    def _on_odom(self, msg):
        self._last_rf2o = msg
        x = msg.pose.pose.position.x - self._offset_x
        y = msg.pose.pose.position.y - self._offset_y
        yaw = _yaw(msg.pose.pose.orientation) - self._offset_yaw
        self._publish_tf(x, y, yaw)

    def _on_initial_pose(self, msg):
        out = PoseWithCovarianceStamped()
        out.header.stamp = self.get_clock().now().to_msg()
        out.header.frame_id = 'map'
        out.pose = msg.pose
        self._slam_pose_pub.publish(out)

        if self._last_rf2o is not None:
            self._offset_x = self._last_rf2o.pose.pose.position.x
            self._offset_y = self._last_rf2o.pose.pose.position.y
            self._offset_yaw = _yaw(self._last_rf2o.pose.pose.orientation)
        else:
            self._offset_x = self._offset_y = self._offset_yaw = 0.0
        self._publish_tf(0.0, 0.0, 0.0)

        yaw = _yaw(msg.pose.pose.orientation)
        self.get_logger().info(
            f'2D Pose: ({msg.pose.pose.position.x:.2f}, {msg.pose.pose.position.y:.2f}) '
            f'yaw={math.degrees(yaw):.1f}° — stand still ~2s')


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
