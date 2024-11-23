# All we need to do so far is copy our terminal config
# We are going to assume that the PersonalMonorepo is already installed

$appDataLocal = $env:LOCALAPPDATA
#TODO we want to move where this gets stored
$personalMonorepoPath = "D:\Users\aidan\Documents\PersonalMonorepo"

$terminalSettingsSource = Join-Path $personalMonorepoPath "windows-setup\terminal-settings.json"
$terminalSettingsDest = Join-Path $appDataLocal "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"


Copy-Item $terminalSettingsSource $terminalSettingsDest