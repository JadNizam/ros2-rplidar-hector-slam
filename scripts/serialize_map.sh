#!/bin/bash
# Posegraph-only save (occupancy grid: use save_map.sh instead).
exec "$(dirname "$0")/save_map.sh" "$@"
