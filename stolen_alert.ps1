$AudioUrl  = "https://famousashtray.com/stuff/stolen_alert.wav"
$AudioPath = "C:\Windows\Temp\stolen_alert.wav"
$LogPath   = "C:\Windows\Temp\stolen_alert.log"

function Write-Log { param($msg) Add-Content -Path $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" }

Write-Log "Stolen laptop script started"

# --- Set volume to max ---
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class AudioHelper {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
    public static void MaxVolume() { for (int i = 0; i < 50; i++) { keybd_event(0xAF, 0, 0, 0); keybd_event(0xAF, 0, 2, 0); } }
}
'@
    [AudioHelper]::MaxVolume()
    Write-Log "Volume maxed"
} catch { Write-Log "Volume set failed: $_" }

# --- Download audio ---
try {
    Invoke-WebRequest -Uri $AudioUrl -OutFile $AudioPath -UseBasicParsing -TimeoutSec 30
    Write-Log "Audio downloaded"
} catch {
    Write-Log "Download failed: $_"
    exit 1
}

# --- Write loop script ---
$loopScriptPath = "C:\Windows\Temp\stolen_loop.ps1"
@'
Add-Type -AssemblyName presentationCore
$path = "C:\Windows\Temp\stolen_alert.wav"
while ($true) {
    try {
        $player = New-Object System.Windows.Media.MediaPlayer
        $player.Open([Uri]$path)
        $player.Volume = 1.0
        $player.Play()
        Start-Sleep -Seconds 10
        $player.Close()
    } catch {
        try {
            $sp = New-Object System.Media.SoundPlayer $path
            $sp.PlaySync()
        } catch {}
    }
}
'@ | Set-Content -Path $loopScriptPath -Encoding UTF8

Write-Log "Loop script written"

# --- Register scheduled task ---
$taskName = "StolenLaptopAlert"

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action   = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$loopScriptPath`""
$trigger1 = New-ScheduledTaskTrigger -AtLogOn
$trigger2 = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest

Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $trigger1,$trigger2 `
    -Settings $settings -Principal $principal `
    -Description "Stolen laptop audio alert" | Out-Null

Write-Log "Scheduled task registered"

# --- Fire immediately if a user is logged in ---
$currentUser = (Get-WmiObject Win32_ComputerSystem).UserName
if ($currentUser) {
    Start-ScheduledTask -TaskName $taskName
    Write-Log "Task started for: $currentUser"
} else {
    Write-Log "No active session - will fire on next logon"
}

Write-Log "Deployment complete"
Write-Host "Done. Log at $LogPath"