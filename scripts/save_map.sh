#!/bin/bash
# Save the current map to maps/

source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_DIR="$SCRIPT_DIR/../maps"
mkdir -p "$MAP_DIR"

MAPNAME="${1:-my_room_$(date +%Y%m%d_%H%M%S)}"
echo "Saving map to: $MAP_DIR/$MAPNAME"

# slam_toolbox publishes /map as a latched (transient_local) topic, so the saver
# MUST subscribe transient_local or it never receives the map and dies with
# "Failed to spin mapsubscription". The default save_map_timeout (2 s) is also
# too short for a large map — give it room.
# Image format: png by default (smaller, viewable anywhere). Pass a 2nd arg to
# override, e.g. `bash scripts/save_map.sh my_room pgm`.
FMT="${2:-png}"

ros2 run nav2_map_server map_saver_cli \
    -f "$MAP_DIR/$MAPNAME" \
    --fmt "$FMT" \
    --ros-args \
    -p save_map_timeout:=20.0 \
    -p map_subscribe_transient_local:=true
echo "Done. Files: $MAP_DIR/$MAPNAME.$FMT + $MAP_DIR/$MAPNAME.yaml"
