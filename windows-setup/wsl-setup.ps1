$homeDir = [Environment]::GetFolderPath('UserProfile')
$filePath = Join-Path -Path $homeDir -ChildPath "WSLFiles\nixos-wsl.tar.gz"

winget install wsl --source msstore

New-Item -Path "~" -Name "WSLFiles" -ItemType "directory" -Force
if (-Not (Test-Path -Path "$filePath" -PathType Leaf)) {
    Invoke-WebRequest https://github.com/nix-community/NixOS-WSL/releases/download/2405.5.4/nixos-wsl.tar.gz -OutFile $filePath
} else {
    Write-Output "Nixos file already exists!"
}
wsl --import NixOS $env:USERPROFILE\NixOS\ $filePath --version 2

wsl -s NixOS