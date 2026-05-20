#!/bin/bash
# serialize_map.sh — Save slam_toolbox native map format for localization
# Run this WHILE mapping is active (slam_toolbox must be running)
# Usage: bash scripts/serialize_map.sh [mapname]
#
# Creates:  maps/<mapname>.posegraph  +  maps/<mapname>.data
# (These are needed for localization mode, different from the PGM/YAML map)

set -e
source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_DIR="$SCRIPT_DIR/../maps"
mkdir -p "$MAP_DIR"

MAPNAME="${1:-slam_map}"
MAPPATH="$MAP_DIR/$MAPNAME"

echo "Serializing slam_toolbox map to: $MAPPATH"
echo "(slam_toolbox must be running — this calls the serialize service)"

ros2 service call /slam_toolbox/serialize_map \
  slam_toolbox/srv/SerializePoseGraph \
  "{filename: '$MAPPATH'}"

echo ""
echo "Done. Files saved:"
ls -lh "$MAP_DIR/$MAPNAME"* 2>/dev/null || echo "  (check $MAPPATH.posegraph and $MAPPATH.data)"
