# Define script names and descriptions as parallel arrays
$scriptNames = @(
    "chocolatey-application-installs.ps1",
    "disable-system-sounds.ps1",
    "windows-explorer-settings.ps1",
    "wsl-setup.ps1",
    "windows-terminal.ps1"
)

$scriptDescriptions = @(
    "Uses chocolatey to install extra packages not provided by the ultimate utility",
    "Disables all system sounds",
    "Shows operating system-protected files",
    "Sets up WSL, as well as the WSL-based backup solution"
    "Configures windows terminal"
)

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

# Run the main function
Execute-ScriptsWithConfirmation