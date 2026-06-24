#!/usr/bin/env python3
"""Publish saved occupancy grid on /map for RViz (transient_local, latched)."""
import os
import sys

import numpy as np
import rclpy
import yaml
from nav_msgs.msg import OccupancyGrid
from PIL import Image
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy


def load_occupancy_grid(yaml_path):
    with open(yaml_path) as f:
        meta = yaml.safe_load(f)

    img_name = meta['image']
    img_path = img_name if os.path.isabs(img_name) else os.path.join(
        os.path.dirname(yaml_path), img_name)
    img_path = os.path.abspath(img_path)
    if not os.path.isfile(img_path):
        base, _ = os.path.splitext(img_path)
        for ext in ('.png', '.pgm', '.ppm'):
            candidate = base + ext
            if os.path.isfile(candidate):
                img_path = candidate
                break
    if not os.path.isfile(img_path):
        raise FileNotFoundError(f'Map image not found: {img_path}')

    img = np.array(Image.open(img_path).convert('L'))

    res = float(meta['resolution'])
    ox, oy, _ = meta['origin']
    negate = int(meta.get('negate', 0))
    occ_thresh = float(meta.get('occupied_thresh', 0.65))
    free_thresh = float(meta.get('free_thresh', 0.196))

    h, w = img.shape
    data = []
    for y in range(h):
        row = img[h - y - 1]
        for px in row:
            # Match nav2 map_io trinary: white=free, black=occupied.
            occ = float(px) / 255.0
            if not negate:
                occ = 1.0 - occ
            if occ > occ_thresh:
                data.append(100)
            elif occ < free_thresh:
                data.append(0)
            else:
                data.append(-1)

    msg = OccupancyGrid()
    msg.header.frame_id = 'map'
    msg.info.resolution = res
    msg.info.width = w
    msg.info.height = h
    msg.info.origin.position.x = float(ox)
    msg.info.origin.position.y = float(oy)
    msg.info.origin.orientation.w = 1.0
    msg.data = data
    return msg


class StaticMapPublisher(Node):
    def __init__(self, yaml_path):
        super().__init__('saved_map_publisher')
        self._grid = load_occupancy_grid(yaml_path)
        # Transient local: standard latched /map QoS (matches nav2 map_server + RViz).
        qos = QoSProfile(
            depth=1,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
            reliability=ReliabilityPolicy.RELIABLE,
        )
        self._pub = self.create_publisher(OccupancyGrid, '/map', qos)
        self._publish()
        # Republish periodically so late RViz subscribers still receive the map.
        self.create_timer(1.0, self._publish)
        self.get_logger().info(
            f'Saved map on /map ({self._grid.info.width}x{self._grid.info.height}) '
            f'from {yaml_path}')

    def _publish(self):
        self._grid.header.stamp = self.get_clock().now().to_msg()
        self._pub.publish(self._grid)


def main():
    yaml_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MAP_YAML')
    if not yaml_path or not os.path.isfile(yaml_path):
        print(f'Map yaml path missing or not found: {yaml_path}', file=sys.stderr)
        sys.exit(1)
    rclpy.init()
    try:
        node = StaticMapPublisher(yaml_path)
    except Exception as exc:
        print(f'Failed to load map from {yaml_path}: {exc}', file=sys.stderr)
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
