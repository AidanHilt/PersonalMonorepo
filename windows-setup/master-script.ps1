# Define script names and descriptions as parallel arrays
$scriptNames = @(
  "setup-default-browser.ps1",
  "chocolatey-application-installs.ps1",
  "disable-system-sounds.ps1",
  "disable-startup-apps.ps1",
  "windows-explorer-settings.ps1",
  "wsl-setup.ps1",
  "desktop-background.ps1",
  "windows-terminal.ps1",
  "smb-setup.ps1"
)

$scriptDescriptions = @(
  "Sets Firefox as the default browser for as many actions as possible",
  "Uses chocolatey to install extra packages not provided by the ultimate utility",
  "Disables all system sounds",
  "Disables certain settings from starting on login",
  "Shows operating system-protected files",
  "Sets up WSL, as well as the WSL-based backup solution",
  "Opens up the desktop background settings for modification",
  "Configures windows terminal",
  "Sets us up to mount homeshare SMB share. Make sure your password manager is ready"
)
function Invoke-Logout {
  Write-Host "Logging out user to apply changes..."
  shutdown.exe /l /f
}

function Check-Documents {
  # Get the current user's Documents folder path
  $documentsPath = [Environment]::GetFolderPath('MyDocuments')
  # Check if Documents folder is on D: drive
  if ($documentsPath -notlike "D:*") {
    Write-Host "Documents folder is not on D: drive. Current location: $documentsPath"
    Write-Host "Attempting to move user profile..."
    
    # Check if the script exists
    if (Test-Path ".\move-user-profile.ps1") {
      try {
        # Execute the move-user-profile script
        & ".\move-user-profile.ps1"
        
        # If script completed successfully, log out
        if ($LASTEXITCODE -eq 0) {
          Write-Host "Profile move script completed successfully. Logging out to apply changes..."
          Invoke-Logout
        } else {
          Write-Error "Profile move script failed with exit code: $LASTEXITCODE"
          exit 1
        }
      }
      catch {
        Write-Error "Failed to execute move-user-profile.ps1: $_"
        exit 1
      }
    } else {
      Write-Error "move-user-profile.ps1 not found in the current directory!"
      exit 1
    }
  } else {
    Write-Host "Documents folder is already on D: drive ($documentsPath). Continuing..."
  }
}

# Function to execute scripts with confirmation
function Execute-ScriptsWithConfirmation {
  # Validate arrays have same length
  if ($scriptNames.Length -ne $scriptDescriptions.Length) {
    Write-Host "Error: Number of scripts and descriptions don't match" -ForegroundColor Red
    return
  }

  # Loop through scripts
  for ($i = 0; $i -lt $scriptNames.Length; $i++) {
    Write-Host "`n=====================================" -ForegroundColor Cyan
    Write-Host "Script: $($scriptNames[$i])" -ForegroundColor Yellow
    Write-Host "Description: $($scriptDescriptions[$i])" -ForegroundColor Yellow
    Write-Host "=====================================`n" -ForegroundColor Cyan

    $confirmation = Read-Host "Do you want to run this script? (Y/N)"
    
    if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
      Write-Host "Executing $($scriptNames[$i])..." -ForegroundColor Green
      try {
        # Execute script in current window with execution policy bypass
        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $scriptNames[$i]
        if (Test-Path $scriptPath) {
          PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
        } else {
          Write-Host "Error: Script file not found at: $scriptPath" -ForegroundColor Red
        }
      }
      catch {
        Write-Host "Error executing script: $_" -ForegroundColor Red
      }
    }
    else {
      Write-Host "Skipping $($scriptNames[$i])" -ForegroundColor Yellow
    }
  }
}

Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted

Check-Documents

$process = Start-Process powershell -ArgumentList "-NoExit", "-Command", "irm christitus.com/win | iex" -PassThru
Wait-Process -Id $process.Id
Write-Host "Chris Titus Utility has completed"

# Run the main function
Execute-ScriptsWithConfirmation