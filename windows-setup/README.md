Welcome to Aidan's Windows setup! Windows is a fucking terrible operating system, that unfortunately is the best option for gaming (IMO at least). That terribleness means we're not going to have a setup script, not even a guided setup script, but a fucking list of instructions. We'll have as much as possible scripted, but boy howdy, this is gonna be a pain.

1. Ultimate Windows Utility setup:
    <ol type="a">
    <li>Open a PowerShell window as an administrator</li>
    <li>Run the following command: <mark>irm "https://christitus.com/win" | iex</mark></li>
    <li>Import the file <mark>ultimate-util-config.json</mark>, and run all the sections. This will take forever</li>
    </ol>

2. Chocolatey install: Since we already installed chocolatey in the previous step, just open a PowerShell window and run the `chocolatey-application-installs` script!