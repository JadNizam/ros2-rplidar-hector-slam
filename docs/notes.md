# Project Notes

## Setup Notes

- RPLiDAR A1 connects via USB and shows up as /dev/ttyUSB0 on Ubuntu. May need udev rules if the port name changes.
- hector_slam doesn't need wheel odometry, which makes it easy to test on a stationary setup or a robot without encoders.
- The default scan frequency on the A1 is 5.5 Hz. Bumping it to 10 Hz improves map quality but uses more CPU.

## Issues Encountered

- [ ] Map drifts when rotating in place quickly — need to slow rotation speed
- [ ] Occasional "laser scan out of range" warnings — may be a USB bandwidth issue

## References

- RPLiDAR ROS 2 driver: https://github.com/Slamtec/rplidar_ros/tree/ros2
- hector_slam paper: Kohlbrecher et al., "A Flexible and Scalable SLAM System with Full 3D Motion Estimation"
- ROS 2 Humble docs: https://docs.ros.org/en/humble/

## Hardware Specs

| Component   | Value              |
|-------------|-------------------|
| LiDAR       | RPLiDAR A1M8      |
| Range       | 0.15 m – 12 m     |
| Scan rate   | 5.5 – 10 Hz       |
| FOV         | 360 degrees        |
| Interface   | USB (UART bridge)  |
