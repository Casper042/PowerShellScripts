# =====================================================================
# Switch MAC Audit Script
# Reads switch list, connects via SSH, runs "no page" + "show mac-address"
# Filters MAC table and exports clean results.
# =====================================================================

# --- Ensure Posh-SSH module is installed ---
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH module not found. Installing..."
    try {
        Install-Module Posh-SSH -Force -Scope CurrentUser -AllowClobber
        Write-Host "Posh-SSH installed successfully."
    }
    catch {
        Write-Error "Failed to install Posh-SSH: $_"
        exit
    }
}

Import-Module Posh-SSH

# --- File Paths (relative to script location) ---
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$inputCSV   = Join-Path $scriptPath "SwitchMACaudit_switches.csv"
$outputCSV  = Join-Path $scriptPath "SwitchMACaudit_output.csv"

# --- Load Switch List ---
if (-not (Test-Path $inputCSV)) {
    Write-Error "Input CSV not found: $inputCSV"
    exit
}

$devices = Import-Csv -Path $inputCSV
$results = @()

foreach ($device in $devices) {
    try {
        Write-Host "Connecting to $($device.Switch)..."

        $securePass = ConvertTo-SecureString $device.Pass -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($device.User, $securePass)

        $session = New-SSHSession -ComputerName $device.Switch -Credential $cred -AcceptKey -ErrorAction Stop
        $stream  = New-SSHShellStream -SessionId $session.SessionId

        # Handle banner or "press any key"
        Start-Sleep -Seconds 2
        $output = $stream.Read()
        if ($output -match 'press any key|continue') {
            $stream.Write("`n")  # send Enter
            Start-Sleep -Seconds 1
        }

        # Disable pagination
        $stream.WriteLine("no page")
        Start-Sleep -Seconds 1
        $null = $stream.Read()

        # Run command
        $stream.WriteLine("show mac-address")
        Start-Sleep -Seconds 3
        $cmdOutput = $stream.Read()
	Write-Host "Output from $($device.Switch)" 
	$cmdOutput
	Write-Host "End of Output from $($device.Switch)" 
        # Parse MAC table lines robustly
        foreach ($line in ($cmdOutput -split "`r?`n")) {
            if ($line -match '^\s*([0-9A-Fa-f]{6}-[0-9A-Fa-f]{6})\s+(\S+)\s+(\S+)\s*$') {
                $results += [PSCustomObject]@{
                    Switch     = $device.Switch
                    MACAddress = $matches[1]
                    Port       = $matches[2]
                    VLAN       = $matches[3]
                }
            }
        }
        Remove-SSHSession -SessionId $session.SessionId
    }
    catch {
        Write-Warning "Failed on $($device.Switch): $_"
    }
}

# --- Export Results ---
$results | Export-Csv -Path $outputCSV -NoTypeInformation
Write-Host "MAC address audit complete. Results saved to: $outputCSV"
