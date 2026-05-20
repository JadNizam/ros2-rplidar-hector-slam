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
