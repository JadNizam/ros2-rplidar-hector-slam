# ROS 2 RPLiDAR SLAM

2D handheld mapping with a Slamtec RPLiDAR C1 and ROS 2 Jazzy. No wheel odometry — motion is estimated from the laser itself with **rf2o laser odometry**, which feeds slam_toolbox a real motion prior so the map tracks you as you walk.

> **Why this matters:** slam_toolbox alone, with a fake static `odom`, has no idea you moved — it starts every scan match from "you didn't move" and under-registers motion, which freezes the pose and ghosts/doubles walls (especially smooth or curved ones). `rf2o_laser_odometry` supplies the missing motion estimate. This is the core architecture; don't replace the rf2o `odom→base_link` with a static identity transform.

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

This installs `rplidar-ros`, `slam-toolbox`, `laser-filters`, `nav2-map-server`, `rviz2`, and **builds `rf2o_laser_odometry` from source** into `ros2_ws/` (it isn't packaged for apt). The build needs internet the first time. The run scripts automatically source this overlay (`ros2_ws/install/setup.bash`); if you ever see a "rf2o overlay not found" warning, re-run `bash scripts/setup.sh`.

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
bash scripts/run_mapping.sh
```

The script sources ROS + rf2o, stops stale nodes, resets the LiDAR, launches, and verifies `/scan`.

RViz2 opens automatically. Walk around the room to build the map.

The default RViz camera is now top-down and fixed on `map`, so the map stays visually static while `base_link`/`laser` move around it.
The colored LaserScan displays are a live history trail; the persistent room shape is the `Map` display on `/map`.

If you need to stop everything manually, run:
```bash
bash scripts/stop_ros.sh
```

**The full 360° scan is used by default** — this is the most important setting for clean, fast room maps. Every scan sees the whole room, so consecutive scans overlap almost completely and the matcher (and rf2o) lock on hard, which is what stops ghost/double walls. Your body/hand is removed by a near-range cutoff (0.45 m), not by throwing away half the scan. Only narrow the sector as a last resort if your body is unavoidably in view and the near-cutoff isn't enough:
```bash
# DEFAULT: full 360° — best for room mapping, nothing to type
bash scripts/run_mapping.sh

# Narrow to front 180° ONLY if your body badly contaminates the rear scan
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-90 front_angle_max_deg:=90

# If the arrow direction is reversed (front becomes rear in RViz):
ros2 launch launch/mapping.launch.py angle_offset_deg:=180
```

---

## 5. Save the Map

In a second terminal (while mapping is still running):
```bash
bash scripts/save_map.sh my_room
```

This saves **both** files localization needs:
- `maps/my_room.posegraph` + `maps/my_room.data` — slam_toolbox serialized map (required for localization)
- `maps/my_room.yaml` + `maps/my_room.png` (or `.pgm`) — occupancy grid for viewing / Nav2

> Don't run bare `map_saver_cli` without the script's QoS/timeout flags — it often fails against slam_toolbox's latched `/map`.

---

## 6. Localization (existing map)

Uses the **same LiDAR startup path as mapping** (`prepare_ros_session.sh` → reset → launch → verify `/scan`). slam_toolbox loads your saved posegraph and publishes `/map`.

**Prerequisites** — save while mapping is still running:
```bash
bash scripts/save_map.sh my_room
```
Needs `maps/my_room.posegraph`, `maps/my_room.data`, and `maps/my_room.yaml`.

**Run localization** (script sources ROS + rf2o automatically — no manual `source` needed):
```bash
bash scripts/stop_ros.sh          # stop mapping first if it is still running
bash scripts/run_localization.sh my_room
```

> If you see `package 'rf2o_laser_odometry' not found`, run `bash scripts/setup.sh` once to build it.

Wait for **"Ready. Map on /map in RViz"** (~10–15 s). The script checks `/scan` before activating slam_toolbox. Walls appear. Click **2D Pose Estimate** at your position, then walk.

**LiDAR not spinning / no `/scan`?** The script retries 3× with full `stop_ros.sh` + LiDAR reset (same as mapping). If it still fails:
```bash
bash scripts/stop_ros.sh
bash scripts/reset_lidar.sh
bash scripts/run_localization.sh my_room
```

**Manual launch:**
```bash
source scripts/source_ros_env.sh
bash scripts/prepare_ros_session.sh
cd ~/ros2-rplidar-hector-slam
ros2 launch launch/localization.launch.py map_file:=$(pwd)/maps/my_room
# optional if not active after ~10 s:
ros2 lifecycle get /slam_toolbox
ros2 lifecycle set /slam_toolbox configure
ros2 lifecycle set /slam_toolbox activate
```

### Localization debug checklist

```bash
source /opt/ros/jazzy/setup.bash
ros2 node list                              # /rplidar, /slam_toolbox, /rf2o_laser_odometry
ros2 topic hz /scan                         # ~7–15 Hz — LiDAR must be running
ros2 topic hz /scan_filtered
ros2 lifecycle get /slam_toolbox            # should be active
ros2 run tf2_ros tf2_echo map odom
ros2 run tf2_ros tf2_echo odom base_link
```

- **No `/scan`** → LiDAR failed (error `80008002`). Run `bash scripts/stop_ros.sh`, unplug/replug USB, `usbipd attach`, then retry.
- Pose frozen → redo 2D Pose Estimate, then stand still 5 s for scan snap.
- Scan not on walls after 5 s → click closer to your real position on the map.
- Walls shifting / weird angles → you walked before 2D Pose Estimate, or moved too fast. Stop, relaunch, set pose again, walk slower.
- Scan 90° off from arrow → `laser_mount_yaw_deg` must match mapping (default `-90` for C1). Re-map if you changed it.
- Pose frozen → confirm you clicked 2D Pose Estimate first; then `ros2 topic hz /odom_rf2o` (~10 Hz).

> The same filtered scan topic (`/scan_filtered`) is used for both mapping and localization, so the geometry slam_toolbox matches is consistent between the two modes.

---

## 7. Walking Procedure (handheld mapping)

Getting a clean map is mostly about *how* you walk, not just the software. The config is now tuned so you can move at a **normal-to-brisk walking pace (~1.5 m/s)** — the limit is set by `correlation_search_space_dimension` and `minimum_time_interval` (see Key Parameters).

- **Keep the LiDAR level** — any tilt smears the 2D scan plane across different heights and creates ghost walls. Hold it flat.
- **Hold it out in front, away from your torso** — the default 0.45 m near-cutoff removes your hand/handle and most of your body while keeping the full 360° of walls. A pole/handle above your head is even better (nothing of you in view at all), but is not required.
- **Walk at a steady ~1.5 m/s** — you no longer need to creep. Just keep the speed *constant*; sudden accelerations are what break tracking, not speed itself.
- **Turn smoothly, don't spin** — sweep corners in a steady arc rather than pivoting in place. The matcher tolerates ~200°/s, but jerky snaps lose track.
- **Start in an open area** — gives the first scan a large, unambiguous reference.
- **Close loops** — return to where you started, and re-enter rooms/junctions you've already mapped. Each revisit lets slam_toolbox close a loop and snap accumulated corridor drift back into place. For a whole building, plan a route that ends where it began.
- **Pause ~1 s at corners, doorways, and junctions** — lets the matcher lock the geometry before the view changes drastically.
- **Avoid glass and mirrors** — LiDAR reflections create phantom walls. If a glass-heavy wing adds phantom walls, drop `max_laser_range`/range filter back to 8.0.
- **Keep a consistent height** — moving the LiDAR up and down mid-walk creates inconsistent scan lines.

### Scanning a whole building (route tips)

- Map **one wing/floor as one continuous walk** — don't stop the node and restart, or you'll get disconnected map fragments.
- Walk each corridor **down one side and back the other**, so both walls get dense coverage and the corridor gets a built-in loop closure.
- At big intersections, **do a slow 360° turn** to tie the corridors together before continuing.
- **Save often** (Section 5) — serialize the posegraph each time you finish a wing, so a single bad turn doesn't cost the whole session.

### Hallways / long corridors (the hard case)

A 2D LiDAR in a blank corridor sees only two parallel walls. It can lock your distance-to-walls and heading, but **not** your position *along* the corridor — every spot looks the same — so the map slips, compresses, or stalls until a non-parallel feature appears. Fixes, in order of impact:

- **Keep an "end" in view.** The far end wall, an intersection, or a doorway is what pins your along-corridor position. For long corridors, **raise `max_laser_range` and the range filter `upper_threshold` to 10–12 m** so the end wall comes into reach (the stable default is 8 m for clean room maps). If no end/feature is within range, the middle *will* drift — keep walking steadily until the next feature appears; don't stop dead in a blank stretch.
- **Mount high + go full 360°.** This is the single biggest win for hallways: from above your body the LiDAR sees *both* ends of the corridor and every doorway at once, which strongly constrains the along-axis position. Handheld at chest height, your body blocks the corridor behind you, throwing away half that constraint.

```bash
# Hallway mode: full 360° FOV (use with an overhead/pole mount so your body isn't in view)
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-180 front_angle_max_deg:=180
```

- **Work the features.** Pause ~1 s at every doorway, recess, pillar, fire extinguisher, or poster — anything that breaks the parallel walls gives the matcher a grip. Doors propped open into rooms are excellent anchors.
- **Do a 360° turn at every junction/intersection** before continuing down a new corridor. This ties the corridors together and gives loop closure something solid.
- **Walk down one side and back the other.** The return trip revisits the corridor and lets loop closure snap out the drift you accumulated on the way down.
- **Laser odometry is now built in.** `rf2o_laser_odometry` gives slam_toolbox a forward-motion estimate that *carries you through* featureless corridors instead of slipping. It still has limits in perfectly blank corridors (no features = nothing to flow against), so the feature/loop-closure tips above still help — but it no longer freezes the moment you walk.

### Tilt / wobble sensitivity (handheld)

A 2D LiDAR only sees one flat slice of the world. When you tilt it while walking, that slice swings up or down, walls appear at slightly wrong ranges, and the scan stops matching the previous one — so SLAM freezes or the map jumps. The config now **tolerates** small tilts, but the real fix is keeping it level:

- **Best fix — keep it level.** Even a flat plate with a stick-on bubble level, a cheap phone gimbal, or resting it on a clipboard held flat removes 90% of the problem.
- **Hold it away from your body, close to your torso's turn axis.** Tucking your elbow in so the LiDAR turns *with you* (instead of swinging on your arm) keeps the plane steady.
- **Software tolerance is set for reliable tracking** (`correlation_search_space_smear_deviation: 0.10`). Note: too much smear (>0.15) backfires — it blurs the match so much the matcher can't tell you moved, and the **map stops growing**. If tilt still breaks tracking, nudge smear to `0.12` only, not higher.

### Walk faster / map bigger (tuning knobs)

In `config/slam_toolbox_lidar_only.yaml`:
- **More tilt/wobble tolerance:** nudge `correlation_search_space_smear_deviation` to `0.12` (not higher — above ~0.15 the map stops growing). Sharper walls (steady mount): lower toward `0.08`.
- **To walk faster:** lower `minimum_time_interval` toward `0.1` and/or raise `correlation_search_space_dimension` toward `0.8`. (Wider search = more CPU and slightly more false-match risk.)
- **For a very large building (sluggish/laggy):** raise `minimum_time_interval` toward `0.25` to keep the pose graph smaller.
- **Maximize the field of view** (best quality, requires a high/pole mount so your body isn't in view):

```bash
# Full 360° — no angular filtering, best scan matching
ros2 launch launch/mapping.launch.py front_angle_min_deg:=-180 front_angle_max_deg:=180
```

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

# Confirm laser odometry is alive (THE thing that makes the pose track you)
ros2 topic hz /odom_rf2o            # expect ~10 Hz
ros2 run tf2_ros tf2_echo odom base_link   # values must change as you move

# View the full TF tree (saves frames.pdf in cwd)
ros2 run tf2_tools view_frames

# Expected chain: map -> odom -> base_link -> laser
# (map->odom from slam_toolbox, odom->base_link from rf2o, base_link->laser static)
ros2 run tf2_ros tf2_echo map laser
```

Or run the bundled diagnostic in one step:
```bash
bash scripts/check_scan.sh
```

---

## 9. Front Scan Filter (removing laptop / body artifacts)

The pipeline still produces `/scan_filtered` for visualization and calibration, and **mapping now uses `/scan_filtered` again** so slam_toolbox sees fewer points and fills the room map more cleanly. Two filters run in sequence:
1. Range filter: removes points closer than 0.45 m (your body/hand/handle) or farther than 8 m
2. Angular bounds filter: full 360° by default (±180°). Narrow it only if your body is unavoidably in view

RViz shows both for comparison:
- **LaserScan (raw)** — orange — full 360° from `/scan`
- **LaserScan (filtered)** — green — front sector only from `/scan_filtered`

**Calibrating the arrow direction:**

1. Place a box or wall directly in front of the physical arrow on the LiDAR.
2. Start mapping: `bash scripts/run_mapping.sh`
3. In RViz, watch **LaserScan (raw)** — the box should appear straight ahead of the red arrow (base_link +X).
4. Watch **LaserScan (filtered)** — the box should still be visible; full 360° is kept by default.
5. Default `laser_mount_yaw_deg:=-90` aligns the C1 physical arrow with the red RViz +X axis.
6. If the box is still off: try `laser_mount_yaw_deg:=0` (90° right) or `laser_mount_yaw_deg:=90` (180° off). Use `angle_offset_deg:=180` only if front/back is reversed.
7. If your body still shows as a blob, raise the near cutoff in `config/laser_filters.yaml` or narrow the sector: `front_angle_max_deg:=60`

> Re-map after changing `laser_mount_yaw_deg` so localization matches.

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
| 5 | Pose freezes / jitters in place, walls double up as you walk | No motion prior — rf2o laser odometry isn't running, so slam_toolbox falls back to "you didn't move" | Confirm rf2o is up: `ros2 topic hz /odom_rf2o` (should be ~10 Hz) and `ros2 run tf2_ros tf2_echo odom base_link` should change as you move. If `/odom_rf2o` is silent, the overlay wasn't sourced — re-run `bash scripts/setup.sh` then relaunch |
| 6 | Scan shows laptop/cable blob | Body blocking part of LiDAR view | Uncomment `sector_block_rear` filter in `laser_filters.yaml` and adjust angles |
| 7 | Map has phantom walls near glass | LiDAR reflecting off windows | Route around glass; reduce `max_laser_range` to 6.0 in the YAML |
| 8 | Map splits or tears | Two TF publishers for same frame | Run `ros2 run tf2_tools view_frames` — check for duplicate edges |
| 9 | Map freezes / stops updating | slam_toolbox not yet active | Script auto-activates after 8 s; check `ros2 lifecycle get /slam_toolbox` |
| 10 | Noisy sparse map | `/scan_filtered` not flowing | Run `ros2 topic hz /scan_filtered` — must be > 0 |

---

## Key Parameters Reference

All in `config/slam_toolbox_lidar_only.yaml`. These defaults are tuned for a **stable, sharp handheld map with no odometry** — pin the walls, keep them put, add new geometry as you move:

| Parameter | Value | Why |
|-----------|-------|-----|
| `throttle_scans` | 1 | Process every scan — there is no wheel odom to fall back on, so every scan matters for tracking motion. |
| `minimum_travel_distance` | 0.2 m | Distance you must move before a new map node is added. Works correctly now because rf2o feeds a **real** `odom→base_link`. (It had to be 0.0 back when `odom` was a static identity TF — that workaround is gone.) Lower toward 0.1 for denser nodes, raise toward 0.3 for big buildings. |
| `minimum_travel_heading` | 0.3 rad | Rotation (~17°) before a new node is added. Same rationale as above. |
| `minimum_time_interval` | 0.2 s | Node-spacing throttle (~5 nodes/s) — steady and stable for normal walking. Lower toward 0.1 only if you walk fast. |
| `max_laser_range` | 8.0 m | Keeps the map clean. Long-range (12 m) C1 returns are weak/noisy and show up as radial speckle that smears the map. Raise to 10–12 only for genuinely large halls. |
| `correlation_search_space_dimension` | 0.5 m | Width of the scan-match search window. Tight = sharp, decisive matches. Wider windows let the pose jump to spurious matches (smearing). |
| `correlation_search_space_smear_deviation` | 0.10 | Match-surface blur. Too high (>0.15) blurs it so much the matcher can't tell you moved and the map stops growing. 0.10 tracks reliably. |
| `link_match_minimum_response_fine` | 0.10 | How good a scan-to-scan match must be to keep the link. Too permissive (<0.1) lets bad matches in and the map smears/ghosts. |
| `angle_variance_penalty` | 1.0 | Lower value = matcher resists random rotation more, so heading stays stable and walls stop smearing into rotated fans. Real turns still register fine. |
| `scan_buffer_size` | 20 | Recent scans kept as the running matching reference. Modest = locks onto your current surroundings (sharp walls) instead of fitting against older geometry (which smears in open rooms). |
| `loop_match_minimum_chain_size` | 12 | Chain length required before attempting a loop closure (strict). |
| `loop_match_minimum_response_coarse` | 0.45 | Coarse loop closure threshold (strict). |
| `loop_match_minimum_response_fine` | 0.55 | Fine loop closure threshold. **Strict on purpose:** a loose value false-closes in repetitive rooms/halls and rotates/folds the whole map (the doubled walls + fan smears). Lower toward 0.50 only if big real loops never get corrected. |
| `loop_search_maximum_distance` | 3.0 m | How far to look for a revisit when closing loops. |
| `map_update_interval` | 0.20 s | How often `/map` is redrawn. Live LaserScan trails still update at full rate. |

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
