$homeDir = [Environment]::GetFolderPath('UserProfile')
$filePath = Join-Path -Path $homeDir -ChildPath "WSLFiles\nixos-wsl.tar.gz"

# ====================================================
# Create the directories that we will sync with rclone
# ====================================================
$directories = @(
  (Join-Path $homeDir "KeePass"),
  (Join-Path $homeDir "Wallpapers")
)

foreach ($dir in $directories) {
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir
    Write-Host "Created directory: $dir"
  } else {
    Write-Host "Directory already exists: $dir"
  }
}
# ====================================================
# We need the microsoft store version of WSL. Whatever
# the ultimate util installs doesn't work with NixOS
# ====================================================
winget install wsl --source msstore


# ====================================================
# Download NixOS WSL, import it, and set it as default
# ====================================================
New-Item -Path "~" -Name "WSLFiles" -ItemType "directory" -Force
if (-Not (Test-Path -Path "$filePath" -PathType Leaf)) {
  Invoke-WebRequest https://github.com/nix-community/NixOS-WSL/releases/download/2405.5.4/nixos-wsl.tar.gz -OutFile $filePath
} else {
  Write-Output "Nixos file already exists!"
}
wsl --import NixOS $env:USERPROFILE\NixOS\ $filePath --version 2

wsl -s NixOS

# ==============================================
# Create our scheduled task that will launch WSL
# ==============================================

# Define task parameters
$taskName = "Launch WSL on Login"
$taskDescription = "Starts Windows Subsystem for Linux when user logs in"
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$action = New-ScheduledTaskAction -Execute "wsl.exe"

# Define settings to prevent multiple instances and set other behaviors
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0) -MultipleInstances IgnoreNew

# Remove existing task if it exists
Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

# Create the new scheduled task
try {
  Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Principal $principal -Trigger $trigger -Action $action -Settings $settings
  Write-Host "Successfully created scheduled task '$taskName'"
} catch {
  Write-Error "Failed to create scheduled task: $_"
  exit 1
}

# Verify the task was created
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
  Write-Host "Verified task creation. Current status: $($task.State)"
} else {
  Write-Error "Task verification failed. Please check Task Scheduler."
}

Set-Clipboard -Value "sudo nixos-rebuild switch --flake github:AidanHilt/PersonalMonorepo/feat/windows-setup/nix/wsl-setup"