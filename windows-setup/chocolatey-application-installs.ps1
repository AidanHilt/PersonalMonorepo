choco install vortex -y
choco install mo2 -y 
choco install openjdk -y 
choco install prismlauncher -y
choco install steelseries-engine -y
choco install lghub -y
choco install virtualbox -y
choco install windirstat -y
# This will probably kill us at some point, but hopefully it's because the package is updatedchoco
choco install parsec -y --checksum 32AB1D25825F510B8BE2BFD73A48D6539DB914A9382726DD486BE114F6CCAE6E
choco install localsend -y
# Welp, as far as I can tell, both the winget and chocolatey packages are broken. Doesn't mean we 
# can't push the install process along
function Get-DefaultBrowser {
    $browserKey = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
    $browserName = (Get-ItemProperty $browserKey).ProgId
    
    switch ($browserName) {
        "ChromeHTML" { return "chrome.exe" }
        "FirefoxURL" { return "firefox.exe" }
        "MSEdgeHTM" { return "msedge.exe" }
        "OperaStable" { return "opera.exe" }
        default { return "iexplore.exe" }
    }
}

# MSI Afterburner download URL
$url = "https://www.msi.com/Landing/afterburner/graphics-cards"

# Get default browser and launch URL
$browser = Get-DefaultBrowser
Start-Process $browser -ArgumentList $url