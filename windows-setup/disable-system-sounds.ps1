# Ensure script is run with administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires administrator privileges. Please run as administrator."
    exit
}

# Registry paths
$soundPath = "HKCU:\AppEvents\Schemes"
$soundProfilePath = "HKCU:\AppEvents\Schemes\Apps\.Default"

try {
    # Set the sound scheme to "No Sounds"
    Set-ItemProperty -Path $soundPath -Name "(Default)" -Value ".None" -ErrorAction Stop
    Write-Host "Sound scheme set to 'No Sounds'"

    # Get all event folders
    $eventFolders = Get-ChildItem -Path $soundProfilePath

    # Loop through each event folder and disable its sounds
    foreach ($folder in $eventFolders) {
        $eventPath = Join-Path $folder.PSPath "\.Current"
        if (Test-Path $eventPath) {
            Set-ItemProperty -Path $eventPath -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
        }
    }

    # Additional registry keys to ensure sounds are disabled
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes\Apps\.Default\.Default\.Current" -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes\Apps\.Default\SystemAsterisk\.Current" -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes\Apps\.Default\SystemExclamation\.Current" -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes\Apps\.Default\SystemHand\.Current" -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes\Apps\.Default\SystemNotification\.Current" -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes\Apps\.Default\SystemQuestion\.Current" -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    
    # Disable Windows startup sound
    $startupPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation"
    if (Test-Path $startupPath) {
        Set-ItemProperty -Path $startupPath -Name "DisableStartupSound" -Value 1 -ErrorAction SilentlyContinue
    }

    Write-Host "All system sounds have been disabled successfully"
    Write-Host "Note: Some applications may need to be restarted for changes to take effect"

} catch {
    Write-Error "An error occurred while disabling sounds: $_"
    exit 1
}