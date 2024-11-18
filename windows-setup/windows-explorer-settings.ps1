# TODO we may not need this, I think the windows util will take care of it
# Ensure script is run with administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires administrator privileges. Please run as administrator."
    exit
}

# Registry paths
$explorerPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

try {
    # Show protected operating system files
    Set-ItemProperty -Path $explorerPath -Name "ShowSuperHidden" -Value 1
    Write-Host "Protected operating system files will now be visible"

    # Restart Windows Explorer to apply changes
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer
    Write-Host "Windows Explorer has been restarted to apply changes"

} catch {
    Write-Error "An error occurred: $_"
    exit 1
}

Write-Host "`nAll settings have been applied successfully. Please check Windows Explorer to verify the changes."