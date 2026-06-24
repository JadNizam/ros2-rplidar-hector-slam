#!/usr/bin/env python3
"""Forward laser scans to slam_toolbox only after 2D Pose Estimate.

slam_toolbox localization crashes if scans arrive before an initial pose
(Mapper FATAL ERROR - unable to get pointer in probability search).
"""
import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from sensor_msgs.msg import LaserScan


class ScanGate(Node):
    def __init__(self):
        super().__init__('scan_gate')
        self._open = False
        self._pending_scan = None

        self._out = self.create_publisher(LaserScan, '/scan_for_slam', 10)
        self.create_subscription(LaserScan, '/scan_filtered', self._on_scan, 10)
        for topic in ('/initialpose', '/initialpose_raw'):
            self.create_subscription(
                PoseWithCovarianceStamped, topic, self._on_initial_pose, 10)

        self.get_logger().info(
            'Blocking /scan_filtered -> /scan_for_slam until 2D Pose Estimate')

    def _on_initial_pose(self, _msg):
        if self._open:
            return
        self.get_logger().info(
            '2D Pose received — releasing scans to slam_toolbox in 0.5s')
        self._gate_timer = self.create_timer(0.5, self._open_gate)

    def _open_gate(self):
        if self._open:
            return
        self._open = True
        if hasattr(self, '_gate_timer'):
            self._gate_timer.cancel()
        self.get_logger().info('Scan gate open — slam_toolbox may localize')
        if self._pending_scan is not None:
            self._out.publish(self._pending_scan)
            self._pending_scan = None

    def _on_scan(self, msg):
        if not self._open:
            self._pending_scan = msg
            return
        self._out.publish(msg)


def main():
    rclpy.init()
    node = ScanGate()
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
