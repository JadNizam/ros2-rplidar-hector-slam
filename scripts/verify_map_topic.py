#!/usr/bin/env python3
"""Exit 0 if /map exists and occupancy cells look sane."""
import os
import sys

import rclpy
from collections import Counter
from nav_msgs.msg import OccupancyGrid
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy

TOPIC = os.environ.get('MAP_TOPIC', '/map')


def main():
    rclpy.init()
    node = Node('verify_map_topic')
    qos = QoSProfile(
        depth=5,
        durability=DurabilityPolicy.TRANSIENT_LOCAL,
        reliability=ReliabilityPolicy.RELIABLE,
    )
    result = {}

    def cb(msg: OccupancyGrid):
        result['cells'] = Counter(msg.data)
        result['size'] = (msg.info.width, msg.info.height)

    node.create_subscription(OccupancyGrid, TOPIC, cb, qos)
    for _ in range(150):
        rclpy.spin_once(node, timeout_sec=0.1)
        if 'cells' in result:
            break

    node.destroy_node()
    rclpy.shutdown()

    if 'cells' not in result:
        print(f'ERROR: {TOPIC} not published.', file=sys.stderr)
        sys.exit(1)

    c = result['cells']
    total = sum(c.values())
    free = c.get(0, 0)
    occ = c.get(100, 0)
    w, h = result['size']
    print(f'{TOPIC} {w}x{h}: free={free} occupied={occ} unknown={c.get(-1, 0)}')

    if occ > total * 0.85:
        print('ERROR: map looks inverted.', file=sys.stderr)
        sys.exit(1)
    print('Map OK for RViz.')


if __name__ == '__main__':
    main()
