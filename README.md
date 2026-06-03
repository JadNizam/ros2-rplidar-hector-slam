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

## Troubleshooting

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
| 5 | Ghost walls from standing still | `minimum_travel_distance` was 0.0 | **Fixed** — now 0.1 m |
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
| `throttle_scans` | 3 | Process every 3rd scan (~3 Hz at 10 Hz scan rate). This is the safe way to limit node insertion rate when there's no odometry — unlike `minimum_travel_distance`, it doesn't require scan matching to be working first. |
| `minimum_travel_distance` | 0.15 m | Minimum movement before a new scan node is inserted. Prevents ghost walls from tiny vibrations or standing still. |
| `minimum_travel_heading` | 0.15 rad | Minimum rotation before a new scan node is inserted. Prevents map smearing when rotating slowly in place. |
| `minimum_time_interval` | 0.5 s | Hard floor: no two consecutive nodes closer than 500 ms. |
| `link_match_minimum_response_fine` | 0.1 | Permissive link acceptance — needed for map building to start in open/sparse rooms. |
| `scan_buffer_size` | 10 | Number of recent scans held in memory for running scan matching. |
| `link_scan_maximum_distance` | 2.0 m | Search radius for nearby graph nodes to link. |
| `loop_match_minimum_chain_size` | 10 | Require a chain of 10 nodes before attempting loop closure. |
| `loop_match_minimum_response_coarse` | 0.35 | Coarse loop closure threshold — conservative to avoid false loop closures. |
| `loop_match_minimum_response_fine` | 0.45 | Fine loop closure threshold. |
| `correlation_search_space_dimension` | 0.5 m | Width of the scan correlation search window. Reduced from 0.7 to prevent aggressive over-matching during slow handheld rotation. |
| `map_update_interval` | 5.0 s | How often the `/map` topic is published. Longer = fewer partial-update artifacts. |

---

## Safe Shutdown

Press **Ctrl+C** once in the terminal running the script. The cleanup handler will:
1. Send SIGTERM to `ros2 launch` (which propagates to all child nodes)
2. Wait for them to exit
3. Run targeted `pkill` on any remaining node processes
4. Print `Shutdown complete.`

If the terminal was closed without Ctrl+C, use:
```bash
bash scripts/stop_ros.sh
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
