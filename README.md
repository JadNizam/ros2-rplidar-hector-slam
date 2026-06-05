# ROS 2 RPLiDAR SLAM

2D mapping with a Slamtec RPLiDAR C1 and ROS 2 Jazzy. No odometry required.

**Hardware:** RPLiDAR C1 → CP2102N USB board → USB-C adapter → Windows laptop (WSL2)

---

## 1. Install ROS 2 Jazzy (WSL2, one time)

```bash
sudo apt update && sudo apt install -y software-properties-common curl
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list
sudo apt update
sudo apt install -y ros-jazzy-desktop
```

---

## 2. Install Project Dependencies (WSL2, one time)

```bash
source /opt/ros/jazzy/setup.bash
bash scripts/setup.sh
```

This installs: `rplidar-ros`, `slam-toolbox`, `laser-filters`, `nav2-map-server`, `rviz2`

Then grant permanent serial port access and **log out and back in**:
```bash
sudo usermod -aG dialout $USER
```

---

## 3. Forward USB from Windows (every session)

> **All commands in this section run in Windows PowerShell — not in WSL2.**
> Open PowerShell as Administrator: Start → search "PowerShell" → Run as administrator.

**First time only — install usbipd-win:**
```powershell
winget install dorssel.usbipd-win
```
Close and reopen PowerShell after installing.

**Find your bus ID:**
```powershell
usbipd list
```
Look for `CP2102N USB to UART Bridge Controller`. Note its `BUSID` (e.g. `2-4`).

**Bind once (first time per device):**
```powershell
usbipd bind --busid 2-4
```

**Attach every session (before using WSL2):**
```powershell
usbipd attach --wsl --busid 2-4
```

**Then back in WSL2, verify the device appeared:**
```bash
ls /dev/ttyUSB0
```

---

## 4. Run Mapping

```bash
source /opt/ros/jazzy/setup.bash
bash scripts/run_mapping.sh
```

RViz2 opens automatically. Walk around the room to build the map.

The default RViz camera is now top-down and fixed on `map`, so the map stays visually static while `base_link`/`laser` move around it.
The colored LaserScan displays are a live history trail; the persistent room shape is the `Map` display on `/map`.

If you need to stop everything manually, run:
```bash
bash scripts/stop_ros.sh
```

The front scan filter is active by default (front 300°) during mapping. To change the sector:
```bash
# Front 120° — tightest, least laptop bleed-through
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-60 front_angle_max_deg:=60

# Front 300° — default for fast, dense room mapping
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-150 front_angle_max_deg:=150

# Front 220° — if you need a bit less rear coverage
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-110 front_angle_max_deg:=110

# Front 180° — if the laptop/body is still contaminating the scan
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-90 front_angle_max_deg:=90

# If the arrow direction is reversed (front becomes rear in RViz):
ros2 launch launch/mapping.launch.py angle_offset_deg:=180
```

---

## 5. Save the Map

In a second terminal:
```bash
source /opt/ros/jazzy/setup.bash
bash scripts/serialize_map.sh my_room
```

This saves `maps/my_room.posegraph` (used for localization).

To also export a standard `.pgm`/`.yaml` image:
```bash
ros2 run nav2_map_server map_saver_cli -f maps/my_room
```

---

## 6. Localization (existing map)

```bash
source /opt/ros/jazzy/setup.bash
bash scripts/run_localization.sh my_room
```

---

## 7. Walking Procedure (handheld mapping)

Getting a clean map is mostly about *how* you walk, not just the software.

- **Keep the LiDAR level** — any tilt smears the 2D scan plane across different heights and creates ghost walls. Hold it flat or mount it on a flat surface.
- **Walk slowly** — aim for 0.5–0.8 m/s. Fast movement outruns the scan matcher.
- **Avoid fast rotation** — turn gradually. Spinning quickly causes scan matching to lose track.
- **Start in an open area** — gives the first scan a large, unambiguous reference.
- **Walk loops when possible** — returning to where you started lets slam_toolbox close the loop and correct accumulated drift.
- **Revisit earlier areas** — every time you walk past a previously mapped section, scan matching tightens up the map.
- **Pause at corners and doorways** — stop for 1–2 seconds so the scan matcher locks in the geometry before you turn.
- **Avoid glass and mirrors** — LiDAR reflections create phantom walls.
- **Keep a consistent height** — moving the LiDAR up and down while walking creates inconsistent scan lines.

---

## 8. Verify Before Running SLAM

Run these **while** `run_mapping.sh` is active (in a second terminal):

```bash
source /opt/ros/jazzy/setup.bash

# Check topics are alive
ros2 topic list | grep -E '/scan|/map'

# Verify scan rate (expect 7–15 Hz for RPLiDAR C1)
ros2 topic hz /scan

# Check frame_id, angle and range values
ros2 topic echo /scan --once

# Confirm filtered scan is flowing to slam_toolbox
ros2 topic hz /scan_filtered

# View the full TF tree (saves frames.pdf in cwd)
ros2 run tf2_tools view_frames

# Expected chain: map -> odom -> base_link -> laser
ros2 run tf2_ros tf2_echo map laser
```

Or run the bundled diagnostic in one step:
```bash
bash scripts/check_scan.sh
```

---

## 9. Front Scan Filter (removing laptop / body artifacts)

The pipeline still produces `/scan_filtered` for visualization and calibration, and **mapping now uses `/scan_filtered` again** so slam_toolbox sees fewer points and fills the room map more cleanly. Two filters run in sequence:
1. Range filter: removes points closer than 0.15 m or farther than 8 m
2. Angular bounds filter: keeps only the front sector for display/cross-checking (default ±150° = front 300° during mapping)

RViz shows both for comparison:
- **LaserScan (raw)** — orange — full 360° from `/scan`
- **LaserScan (filtered)** — green — front sector only from `/scan_filtered`

**Calibrating the arrow direction:**

1. Place a box or wall directly in front of the physical arrow on the LiDAR.
2. Start mapping: `bash scripts/run_mapping.sh`
3. In RViz, watch **LaserScan (raw)** — the box should appear near angle 0 (straight ahead in RViz).
4. Watch **LaserScan (filtered)** — the box should still be visible; the rear half should be empty.
5. If the box disappears and the laptop shows up instead, the arrow is reversed — relaunch with `angle_offset_deg:=180`.
6. If the laptop is still partially visible on one side, narrow the sector: `front_angle_max_deg:=60`

**Checking what SLAM uses:**
```bash
ros2 topic echo /scan_filtered --once | grep frame_id
ros2 topic hz /scan_filtered
# Mapping mode should subscribe to /scan_filtered for cleaner map filling:
ros2 topic info /scan_filtered
```

**Sector presets** (edit `config/laser_filters.yaml` filter2.params to change the default):

| FOV | `lower_angle` | `upper_angle` | Use when |
|-----|--------------|--------------|----------|
| 120° | -1.0472 | 1.0472 | Laptop is very close to LiDAR |
| 180° | -1.5708 | 1.5708 | Default — good for most setups |
| 220° | -1.9199 | 1.9199 | Long hallways, need more side coverage |

---

**`/dev/ttyUSB0` not found**
- Run in PowerShell (admin): `usbipd attach --wsl --busid 2-4`
- Verify: `ls /dev/ttyUSB*`

**Permission denied on `/dev/ttyUSB0`**
```bash
sudo chmod 777 /dev/ttyUSB0
```

**Lidar spins but no `/scan` topic**
- C1 baud rate is 460800 — confirm in `launch/mapping.launch.py`
- Try: `ros2 launch rplidar_ros view_rplidar_c1_launch.py`

**RViz shows nothing**
- Fixed Frame must be `map`
- Run `ros2 topic hz /scan` — should be 7–15 Hz
- Wait ~5 seconds for slam_toolbox to initialize

**`laser_filters` package not found**
```bash
sudo apt install ros-jazzy-laser-filters
```

---

## Ghost Walls / Noisy Map Debug Checklist

Work through these in order — each one is a likely cause:

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | Doubled walls, smearing | LiDAR tilted | Hold/mount it perfectly level |
| 2 | Doubled walls, smearing | Walking too fast | Slow down to 0.5–0.8 m/s |
| 3 | Walls drift or rotate | No static `base_link`→`laser` TF | Already included in launch — run `ros2 run tf2_tools view_frames` to confirm |
| 4 | Map jumps sideways | False loop closure | Raise `loop_match_minimum_response_fine` in `slam_toolbox_lidar_only.yaml` |
| 5 | Ghost walls from standing still | `minimum_travel_distance` was 0.0 | **Fixed** — now 0.005 m |
| 6 | Scan shows laptop/cable blob | Body blocking part of LiDAR view | Uncomment `sector_block_rear` filter in `laser_filters.yaml` and adjust angles |
| 7 | Map has phantom walls near glass | LiDAR reflecting off windows | Route around glass; reduce `max_laser_range` to 6.0 in the YAML |
| 8 | Map splits or tears | Two TF publishers for same frame | Run `ros2 run tf2_tools view_frames` — check for duplicate edges |
| 9 | Map freezes / stops updating | slam_toolbox not yet active | Script auto-activates after 8 s; check `ros2 lifecycle get /slam_toolbox` |
| 10 | Noisy sparse map | `/scan_filtered` not flowing | Run `ros2 topic hz /scan_filtered` — must be > 0 |

---

## Key Parameters Reference

All in `config/slam_toolbox_lidar_only.yaml`:

| Parameter | Value | Why |
|-----------|-------|-----|
| `throttle_scans` | 3 | Process every third scan so walls are not stamped into the map too aggressively. |
| `minimum_travel_distance` | 0.1 m | Minimum movement before a new scan node is inserted. Requires real walking movement, not vibration. |
| `minimum_travel_heading` | 0.08 rad (~4.6°) | Minimum rotation before a new scan node is inserted. Prevents node spam from tiny jiggles. |
| `minimum_time_interval` | 0.1 s | Hard floor: no two consecutive nodes closer than 100 ms. |
| `link_match_minimum_response_fine` | 0.1 | Permissive link acceptance — needed for map building to start in open/sparse rooms. |
| `scan_buffer_size` | 30 | Number of recent scans held in memory for running scan matching and free-space estimation. |
| `link_scan_maximum_distance` | 2.0 m | Search radius for nearby graph nodes to link. |
| `loop_match_minimum_chain_size` | 10 | Require a chain of 10 nodes before attempting loop closure. |
| `loop_match_minimum_response_coarse` | 0.25 | Coarse loop closure threshold — looser for quicker room stitching. |
| `loop_match_minimum_response_fine` | 0.35 | Fine loop closure threshold. |
| `correlation_search_space_dimension` | 0.5 m | Width of the scan correlation search window. Reduced from 0.7 to prevent aggressive over-matching during slow handheld rotation. |
| `map_update_interval` | 0.1 s | How often the `/map` topic is published. The grey occupancy grid is the persistent map — the LaserScan displays are live-only trails (0.3 s decay). |

---

## Safe Shutdown

Press **Ctrl+C** once in the terminal running the script. The cleanup handler will:
1. Send SIGTERM to `rplidar_composition` first and wait 2 s for the motor to stop
2. Kill the `ros2 launch` process and wait for it to exit
3. Run targeted `pkill` on any remaining node processes
4. Print `Shutdown complete.`

If the terminal was closed without Ctrl+C, use:
```bash
bash scripts/stop_ros.sh
```

Equivalent kill-all command:
```bash
pkill -SIGTERM -f rplidar_composition
sleep 2
pkill -f async_slam_toolbox_node
pkill -f localization_slam_toolbox_node
pkill -f scan_to_scan_filter_chain
pkill -f static_transform_publisher
pkill -f rviz2
pkill -f "ros2 launch"
pkill -SIGKILL -f rplidar_composition
pkill -SIGKILL -f async_slam_toolbox_node
pkill -SIGKILL -f localization_slam_toolbox_node
pkill -SIGKILL -f scan_to_scan_filter_chain
pkill -SIGKILL -f static_transform_publisher
pkill -SIGKILL -f rviz2
pkill -SIGKILL -f "ros2 launch"
```

Verify everything stopped:
```bash
ros2 node list
# should return nothing (or only unrelated nodes)
```

---

## Debug TF and Scan

Run these **while** a launch script is active (in a second terminal):

```bash
source /opt/ros/jazzy/setup.bash

# Full TF tree — saves frames.pdf in current directory
ros2 run tf2_tools view_frames

# Confirm the chain: map -> odom -> base_link -> laser
ros2 run tf2_ros tf2_echo map laser
ros2 run tf2_ros tf2_echo base_link laser

# Check scan frame and rate
ros2 topic echo /scan --once | grep frame_id
ros2 topic hz /scan

# Check filtered scan is flowing into slam_toolbox
ros2 topic hz /scan_filtered
```

Expected TF chain: `map` → `odom` → `base_link` → `laser`

If you see two XYZ axes in RViz at different positions, the most common causes are:
- A previous session did not shut down cleanly — run `bash scripts/stop_ros.sh` first
- The `map` origin axis and the robot's current pose axis are simply two different frames (this is normal — `map` is fixed at origin, `base_link`/`laser` move with you)
