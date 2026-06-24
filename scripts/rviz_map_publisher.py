#!/usr/bin/env python3
"""Load saved map yaml and publish /map for RViz (volatile, continuous republish).

WSL/RViz often miss transient-local latched maps; republishing volatile fixes
"No map received" while keeping correct nav2 trinary cell values.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rclpy
from nav_msgs.msg import OccupancyGrid
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy

from static_map_publisher import load_occupancy_grid


class RvizMapPublisher(Node):
    def __init__(self, yaml_path):
        super().__init__('rviz_map_publisher')
        self._grid = load_occupancy_grid(yaml_path)
        qos = QoSProfile(
            depth=10,
            durability=DurabilityPolicy.VOLATILE,
            reliability=ReliabilityPolicy.RELIABLE,
        )
        self._pub = self.create_publisher(OccupancyGrid, '/map', qos)
        self._publish()
        self.create_timer(0.2, self._publish)  # 5 Hz
        self.get_logger().info(
            f'RViz map on /map ({self._grid.info.width}x{self._grid.info.height}) '
            f'from {yaml_path}')

    def _publish(self):
        self._grid.header.stamp = self.get_clock().now().to_msg()
        self._pub.publish(self._grid)


def main():
    yaml_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MAP_YAML')
    if not yaml_path or not os.path.isfile(yaml_path):
        print(f'Map yaml missing: {yaml_path}', file=sys.stderr)
        sys.exit(1)
    rclpy.init()
    try:
        node = RvizMapPublisher(yaml_path)
    except Exception as exc:
        print(f'Failed to load map: {exc}', file=sys.stderr)
        rclpy.shutdown()
        sys.exit(1)
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
