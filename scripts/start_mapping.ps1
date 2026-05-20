# start_mapping.ps1 — Full RPLIDAR + SLAM launcher for Windows
# Run from PowerShell: .\scripts\start_mapping.ps1
# 
# This script:
#   1. Kills any leftover ROS nodes in WSL
#   2. Detaches + re-attaches RPLIDAR USB (resets motor state)
#   3. Launches the full ROS 2 SLAM pipeline in WSL

param(
    [string]$BusId = "2-4"
)

$ErrorActionPreference = "Continue"

# Ensure usbipd is on PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "=== RPLIDAR SLAM Launcher ===" -ForegroundColor Cyan

# Step 1: Kill leftover ROS nodes in WSL
Write-Host "[1/4] Killing any leftover ROS nodes..." -ForegroundColor Yellow
wsl bash -c "sudo pkill -9 -f 'rplidar|slam_toolbox|scan_to_scan|rviz2' 2>/dev/null; true"
Start-Sleep -Seconds 1

# Step 2: Detach USB to reset RPLIDAR motor state
Write-Host "[2/4] Detaching RPLIDAR USB (bus $BusId) to reset device..." -ForegroundColor Yellow
usbipd detach --busid $BusId 2>&1 | Out-Null
Start-Sleep -Seconds 2

# Step 3: Re-attach USB
Write-Host "[3/4] Re-attaching RPLIDAR USB..." -ForegroundColor Yellow
$attachResult = usbipd attach --wsl --busid $BusId 2>&1
Write-Host $attachResult

# Wait for /dev/ttyUSB0 to appear in WSL
Write-Host "[4/4] Waiting for /dev/ttyUSB0..." -ForegroundColor Yellow
$maxWait = 15
$waited = 0
do {
    Start-Sleep -Seconds 1
    $waited++
    $found = wsl bash -c "test -e /dev/ttyUSB0 && echo yes || echo no" 2>/dev/null
} while ($found -ne "yes" -and $waited -lt $maxWait)

if ($found -ne "yes") {
    Write-Host "ERROR: /dev/ttyUSB0 not found after $maxWait seconds." -ForegroundColor Red
    Write-Host "Check that the RPLIDAR is plugged in and usbipd bind was run." -ForegroundColor Red
    exit 1
}

Write-Host "/dev/ttyUSB0 found. Setting permissions..." -ForegroundColor Green
wsl bash -c "sudo chmod 777 /dev/ttyUSB0"

# Step 4: Launch
Write-Host "" 
Write-Host "Launching: RPLIDAR C1 -> laser_filter -> slam_toolbox -> RViz" -ForegroundColor Green
Write-Host "(slam_toolbox will auto-configure at 4s and activate at 7s)" -ForegroundColor Gray
Write-Host ""

$repoPath = Split-Path -Parent $PSScriptRoot
wsl bash -c "source /opt/ros/jazzy/setup.bash; cd '$($repoPath -replace '\\','/' -replace 'C:','/mnt/c')'; ros2 launch launch/mapping.launch.py 2>&1"
