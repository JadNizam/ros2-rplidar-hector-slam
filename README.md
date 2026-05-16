# ROS 2 RPLiDAR SLAM

2D mapping and localization using a Slamtec RPLiDAR and ROS 2. No GPS required. The goal is to build an occupancy grid map of an indoor environment and localize within it in real time.

---

## Hardware

- Slamtec RPLiDAR A1 (or A2/A3)
- Computer running Ubuntu 22.04
- USB cable for LiDAR connection

## Software

- ROS 2 Humble
- [rplidar_ros](https://github.com/Slamtec/rplidar_ros/tree/ros2) — RPLiDAR driver for ROS 2
- [hector_slam](http://wiki.ros.org/hector_slam) (ported to ROS 2) — scan-matching based SLAM, no odometry needed
- RViz2 — visualization
- Python 3.10+

---

## Setup

Clone the repo and run the setup script to install dependencies:

```bash
git clone https://github.com/YOUR_USERNAME/ros2-rplidar-hector-slam.git
cd ros2-rplidar-hector-slam
bash scripts/setup.sh
```

Make sure your LiDAR is plugged in and the serial port has the right permissions:

```bash
sudo chmod 777 /dev/ttyUSB0
```

---

## Running

Build the workspace, then launch the mapping session:

```bash
bash scripts/run_mapping.sh
```

Or manually:

```bash
source /opt/ros/humble/setup.bash
ros2 launch launch/mapping.launch.py
```

Open RViz2 and load `rviz/mapping.rviz` to visualize the map being built.

To save a map once you're done scanning:

```bash
ros2 run nav2_map_server map_saver_cli -f maps/my_map
```

---

## Project Structure

```
ros2-rplidar-hector-slam/
├── config/         # SLAM and sensor parameters
├── docs/           # Notes and references
├── launch/         # ROS 2 launch files
├── maps/           # Saved map files (.pgm + .yaml)
├── media/          # Screenshots and demo footage
├── rviz/           # RViz2 config files
└── scripts/        # Shell scripts for setup and running
```

---

## Future Improvements

- Add AMCL localization on a pre-built map (nav2 stack)
- Test with RPLiDAR A2 for better range and accuracy
- Add a simple waypoint navigation demo
- Try slam_toolbox as an alternative to hector_slam
