# Get current user's registry path for startup apps
$startupRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

# Define apps to disable
$appsToDisable = @(
    "MicrosoftEdgeAutoLaunch_519EAD7EDD2820EA5C840662A97D7643",
    "OneDrive",
    "GalaxyClient",
    "GogGalaxy"
)

# Remove each app from startup
foreach ($app in $appsToDisable) {
    # Check if the app exists in startup
    if (Get-ItemProperty -Path $startupRegPath -Name $app -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $startupRegPath -Name $app
        Write-Host "Disabled startup for: $app"
    } else {
        Write-Host "$app not found in startup"
    }
}