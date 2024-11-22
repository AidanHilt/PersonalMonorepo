# Prompt for credentials
$smbAddress = Read-Host "Enter SMB server address (e.g. \\server\share)"
$username = Read-Host "Enter username"
$password = Read-Host "Enter password"

# Create the SMB mapping that persists across reboots
try {
  New-SmbMapping -LocalPath "Y:" `
                -RemotePath $smbAddress `
                -Persistent $true `
                -UserName $username `
                -Password $password

  Write-Host "SMB mapping created successfully."

  # Restart Windows Explorer to apply changes
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Process explorer
  Write-Host "Windows Explorer has been restarted to apply changes"
} catch {
  Write-Error "Failed to create SMB mapping: $_"
}