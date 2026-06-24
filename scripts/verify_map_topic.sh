#!/bin/bash
# Fail if /map is missing or looks inverted (almost all cells occupied).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/source_ros_env.sh"
python3 "$SCRIPT_DIR/verify_map_topic.py"
