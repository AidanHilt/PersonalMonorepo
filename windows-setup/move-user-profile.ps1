# Requires -RunAsAdministrator

# Get current user information
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$username = ($currentUser -split '\\')[1]

# Define paths
$oldUserProfile = $env:USERPROFILE
$newUserProfile = "D:\Users\$username"

# Verify D: drive exists
if (-not (Test-Path "D:\")) {
    Write-Error "D: drive not found. Please ensure the destination drive exists."
    exit 1
}

# Create new directory structure
try {
    New-Item -Path $newUserProfile -ItemType Directory -Force
    
    # Create standard user folders
    $folders = @(
        'Desktop',
        'Documents',
        'Downloads',
        'Pictures',
        'Music',
        'Videos'
    )
    
    foreach ($folder in $folders) {
        New-Item -Path "$newUserProfile\$folder" -ItemType Directory -Force
    }
} catch {
    Write-Error "Failed to create directory structure: $_"
    exit 1
}

# Stop Windows Explorer to prevent file locks
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

# Move user profile content
try {
    robocopy $oldUserProfile $newUserProfile /E /COPYALL /XJ /R:1 /W:1
} catch {
    Write-Error "Failed to copy user profile: $_"
    exit 1
}

# Update registry settings
try {
    
    # Update Shell Folders locations
    $shellFolders = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
    $userShellFolders = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    
    # Update paths for both Shell Folders keys
    @($shellFolders, $userShellFolders) | ForEach-Object {
        Set-ItemProperty -Path $_ -Name "Desktop" -Value "$newUserProfile\Desktop"
        Set-ItemProperty -Path $_ -Name "Personal" -Value "$newUserProfile\Documents"
        Set-ItemProperty -Path $_ -Name "My Pictures" -Value "$newUserProfile\Pictures"
        Set-ItemProperty -Path $_ -Name "My Music" -Value "$newUserProfile\Music"
        Set-ItemProperty -Path $_ -Name "My Video" -Value "$newUserProfile\Videos"
        Set-ItemProperty -Path $_ -Name "{374DE290-123F-4565-9164-39C4925E467B}" -Value "$newUserProfile\Downloads"
    }
} catch {
    Write-Error "Failed to update registry settings: $_"
    exit 1
}

# Move and update Recycle Bin
try {
    # Create new Recycle Bin directory
    New-Item -Path "D:\`$Recycle.Bin" -ItemType Directory -Force

    # Get user SID
    $userSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

    # Move existing Recycle Bin contents
    if (Test-Path "C:\`$Recycle.Bin\$userSid") {
        Move-Item "C:\`$Recycle.Bin\$userSid" "D:\`$Recycle.Bin\" -Force
    }
} catch {
    Write-Error "Failed to move Recycle Bin: $_"
    exit 1
}

# Restart Explorer
Start-Process explorer

Write-Host "Profile migration completed successfully. Please log off and log back on for changes to take effect."
Write-Host "Note: Some applications may need to be reconfigured to use the new locations."