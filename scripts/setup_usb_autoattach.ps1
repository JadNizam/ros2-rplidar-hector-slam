# Run this ONCE in Windows PowerShell (Admin) to auto-attach the LiDAR on every login.
# Usage: Right-click → Run as Administrator

param(
    [string]$BusId = ""
)

# Ensure usbipd is installed
if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Host "usbipd not found. Installing..." -ForegroundColor Yellow
    winget install dorssel.usbipd-win
    Write-Host "Restart PowerShell as Admin and re-run this script." -ForegroundColor Cyan
    exit 1
}

# Auto-detect the CP2102N device if BusId not provided
if (-not $BusId) {
    $device = usbipd list | Select-String "CP2102"
    if ($device) {
        $BusId = ($device -split "\s+")[0]
        Write-Host "Detected CP2102N at bus ID: $BusId" -ForegroundColor Green
    } else {
        Write-Host "CP2102N device not found. Plug in the LiDAR and re-run, or pass -BusId manually." -ForegroundColor Red
        Write-Host "Available devices:" -ForegroundColor Yellow
        usbipd list
        exit 1
    }
}

# Bind the device (safe to run multiple times)
Write-Host "Binding $BusId..." -ForegroundColor Yellow
usbipd bind --busid $BusId

# Create the scheduled task
$taskName = "LiDAR-USBForward-WSL2"
$script = "usbipd attach --wsl --busid $BusId"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -NonInteractive -Command `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

# Remove old task if it exists
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Description "Auto-forward RPLiDAR USB to WSL2 at login" | Out-Null

Write-Host ""
Write-Host "Done! Task '$taskName' registered." -ForegroundColor Green
Write-Host "The LiDAR will attach to WSL2 automatically on every Windows login." -ForegroundColor Green
Write-Host ""
Write-Host "Attaching now for this session..." -ForegroundColor Yellow
usbipd attach --wsl --busid $BusId
Write-Host "Check WSL2: ls /dev/ttyUSB0" -ForegroundColor Cyan
