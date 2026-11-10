<#
.SYNOPSIS
    WinOpt - Audit reseau / processus / applications + cleanup reversible (100% natif Windows, PS 5.1+)

.EXAMPLE
    .\WinOpt.ps1                         # menu interactif
    .\WinOpt.ps1 -Mode Network -Seconds 60
    .\WinOpt.ps1 -Mode Processes
    .\WinOpt.ps1 -Mode Apps
    .\WinOpt.ps1 -Mode Cleanup           # dry-run (rien n'est modifie)
    .\WinOpt.ps1 -Mode Cleanup -Apply    # applique (point de restauration + fichier undo)
    .\WinOpt.ps1 -Mode Rollback          # annule le dernier cleanup

    Lancer dans une console PowerShell *administrateur* pour des resultats complets.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Network','Processes','Apps','Cleanup','Rollback','All')]
    [string]$Mode = 'Menu',
    [int]$Seconds = 30,
    [switch]$Apply,
    [switch]$ResolveDns,
    [string]$OutDir = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'WinOpt')
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:SigCache = @{}
$script:LastNet  = @()

# ---------------------------------------------------------------- Windows Update : INTOUCHABLE
$WU_Services = @('wuauserv','UsoSvc','BITS','DoSvc','WaaSMedicSvc','TrustedInstaller','CryptSvc','msiserver','sppsvc','InstallService','LicenseManager')
$WU_Processes = @('svchost','TiWorker','TrustedInstaller','MoUsoCoreWorker','usocoreworker','UsoClient','wuauclt','MusNotification','MusNotificationUx','SIHClient','WaaSMedic','DeviceCensus')
$Protected_Services = $WU_Services + @('DcomLaunch','RpcSs','RpcEptMapper','Dnscache','Dhcp','BFE','mpssvc','WinDefend','EventLog','LanmanWorkstation','LanmanServer','nsi','NlaSvc','netprofm','Winmgmt','PlugPlay','Power','ProfSvc','Schedule','SamSs','lsass','gpsvc','UserManager','StateRepository','TimeBrokerSvc','CoreMessagingRegistrar','SystemEventsBroker','W32Time','wlansvc','WlanSvc','Audiosrv','AudioEndpointBuilder')

function Show-Header($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Save-Csv($data, $name) {
    $f = Join-Path $OutDir "$name`_$script:Stamp.csv"
    $data | Export-Csv -Path $f -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "  -> export : $f" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- Classification natif / pas natif
function Get-Origin([string]$path) {
    if ([string]::IsNullOrEmpty($path)) { return 'Systeme/Inconnu' }
    if ($script:SigCache.ContainsKey($path)) { return $script:SigCache[$path] }
    $subj = ''
    $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction SilentlyContinue
    if ($sig -and $sig.SignerCertificate) { $subj = $sig.SignerCertificate.Subject }
    $inWin = $path.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)
    if ($subj -match 'CN=Microsoft Windows' -or ($inWin -and $subj -match 'O=Microsoft Corporation')) { $r = 'Natif' }
    elseif ($inWin -and -not $subj) { $r = 'Natif (non signe/catalogue)' }
    elseif ($subj -match 'O=Microsoft Corporation') { $r = 'Microsoft (hors OS)' }
    elseif ($subj) { $r = 'Tiers' }
    else { $r = 'Tiers (non signe)' }
    $script:SigCache[$path] = $r
    return $r
}
function Test-IsNative($origin) { return ($origin -like 'Natif*') }

# ---------------------------------------------------------------- 1. RESEAU
function Get-IoSnapshot {
    $h = @{}
    Get-CimInstance Win32_Process | ForEach-Object {
        $h[[int]$_.ProcessId] = @{ Name = $_.Name; Path = $_.ExecutablePath; Bytes = [double]($_.ReadTransferCount + $_.WriteTransferCount + $_.OtherTransferCount) }
    }
    return $h
}

function Invoke-NetScan {
    param([int]$Sec = 30)
    Show-Header "FLUX RESEAU - fenetre de $Sec s"
    if (-not $script:IsAdmin) { Write-Host "  (non-admin : certains processus systeme seront inconnus)" -ForegroundColor Yellow }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    $s0 = @{}; foreach ($a in $adapters) { $s0[$a.Name] = Get-NetAdapterStatistics -Name $a.Name }
    $io0 = Get-IoSnapshot
    $conns = @{}
    $t0 = Get-Date
    Write-Host "  Capture en cours..." -ForegroundColor DarkGray
    do {
        foreach ($c in (Get-NetTCPConnection -State Established)) {
            if ($c.RemoteAddress -in @('127.0.0.1','::1','0.0.0.0','::')) { continue }
            $k = "$($c.OwningProcess)|$($c.RemoteAddress):$($c.RemotePort)"
            $conns[$k] = @{ Pid = [int]$c.OwningProcess; Remote = "$($c.RemoteAddress):$($c.RemotePort)"; Addr = $c.RemoteAddress }
        }
        Start-Sleep -Seconds ([math]::Min(3, [math]::Max(1, $Sec)))
    } while (((Get-Date) - $t0).TotalSeconds -lt $Sec)
    $el = [math]::Max(1, ((Get-Date) - $t0).TotalSeconds)
    $io1 = Get-IoSnapshot

    # --- Global par carte (exact)
    $rows = foreach ($a in $adapters) {
        $s1 = Get-NetAdapterStatistics -Name $a.Name
        $dIn = $s1.ReceivedBytes - $s0[$a.Name].ReceivedBytes
        $dOut = $s1.SentBytes - $s0[$a.Name].SentBytes
        [pscustomobject]@{
            Carte = $a.Name
            'IN KB/s' = [math]::Round($dIn / $el / 1KB, 1)
            'OUT KB/s' = [math]::Round($dOut / $el / 1KB, 1)
            'IN fenetre MB' = [math]::Round($dIn / 1MB, 2)
            'OUT fenetre MB' = [math]::Round($dOut / 1MB, 2)
            'IN depuis boot GB' = [math]::Round($s1.ReceivedBytes / 1GB, 2)
            'OUT depuis boot GB' = [math]::Round($s1.SentBytes / 1GB, 2)
        }
    }
    Write-Host "`n[Global par carte - octets reels]" -ForegroundColor Green
    $rows | Format-Table -AutoSize
    Save-Csv $rows 'net_adapters'

    # --- Par processus
    $udp = @{}; Get-NetUDPEndpoint | Group-Object OwningProcess | ForEach-Object { $udp[[int]$_.Name] = $_.Count }
    $byPid = $conns.Values | Group-Object { $_.Pid }
    $res = foreach ($g in $byPid) {
        $procId = [int]$g.Name
        $info = $io1[$procId]; if (-not $info) { continue }
        $b0 = 0; if ($io0.ContainsKey($procId)) { $b0 = $io0[$procId].Bytes }
        $remotes = @($g.Group | ForEach-Object { $_.Remote } | Select-Object -Unique)
        $shown = $remotes | Select-Object -First 3
        if ($ResolveDns) {
            $shown = $g.Group | Select-Object -First 3 | ForEach-Object {
                $n = $null; try { $n = [Net.Dns]::GetHostEntry($_.Addr).HostName } catch {}
                if ($n) { "$n`:$($_.Remote.Split(':')[-1])" } else { $_.Remote }
            }
        }
        $origin = Get-Origin $info.Path
        $u = 0; if ($udp.ContainsKey($procId)) { $u = $udp[$procId] }
        [pscustomobject]@{
            Process = $info.Name; PID = $procId; Origine = $origin
            'IO KB/s (proxy)' = [math]::Round(($info.Bytes - $b0) / $el / 1KB, 1)
            TCP = $remotes.Count; UDP = $u
            Destinations = ($shown -join ' ')
            Chemin = $info.Path
        }
    }
    $res = @($res | Sort-Object 'IO KB/s (proxy)' -Descending)
    $script:LastNet = $res
    Write-Host "[Processus avec connexions sortantes etablies]" -ForegroundColor Green
    Write-Host "  'IO KB/s (proxy)' = delta des compteurs I/O du processus (lecture+ecriture+autre) : indicatif, pas separe IN/OUT." -ForegroundColor DarkGray
    $res | Select-Object Process, PID, Origine, 'IO KB/s (proxy)', TCP, UDP, Destinations | Format-Table -AutoSize -Wrap
    Save-Csv $res 'net_processes'

    # --- Ports en ecoute exposes
    $listen = Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -notin @('127.0.0.1','::1') } | ForEach-Object {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)"
        [pscustomobject]@{ Port = $_.LocalPort; Adresse = $_.LocalAddress; Process = $p.Name; PID = $_.OwningProcess; Origine = (Get-Origin $p.ExecutablePath) }
    } | Sort-Object Port -Unique
    Write-Host "[Ports en ecoute exposes au reseau]" -ForegroundColor Green
    $listen | Format-Table -AutoSize
    Save-Csv $listen 'net_listening'
}

# ---------------------------------------------------------------- 2. PROCESSUS
function Invoke-ProcScan {
    Show-Header "PROCESSUS"
    if (-not $script:IsAdmin) { Write-Host "  (non-admin : chemins systeme inaccessibles -> 'Systeme/Inconnu')" -ForegroundColor Yellow }
    $cores = [Environment]::ProcessorCount
    $a = @{}; Get-Process | ForEach-Object { if ($_.TotalProcessorTime) { $a[$_.Id] = $_.TotalProcessorTime.TotalSeconds } }
    Start-Sleep -Seconds 3
    $cim = @{}; Get-CimInstance Win32_Process | ForEach-Object { $cim[[int]$_.ProcessId] = $_ }
    $svc = @{}
    Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -gt 0 } | ForEach-Object {
        $k = [int]$_.ProcessId; if (-not $svc.ContainsKey($k)) { $svc[$k] = New-Object System.Collections.ArrayList }
        [void]$svc[$k].Add($_.Name)
    }
    $rows = Get-Process | ForEach-Object {
        $p = $_; $path = $null
        if ($cim.ContainsKey($p.Id)) { $path = $cim[$p.Id].ExecutablePath }
        $cpu = 0
        if ($a.ContainsKey($p.Id) -and $p.TotalProcessorTime) { $cpu = [math]::Round((($p.TotalProcessorTime.TotalSeconds - $a[$p.Id]) / 3 / $cores) * 100, 1) }
        $s = ''; if ($svc.ContainsKey($p.Id)) { $s = ($svc[$p.Id] -join ',') }
        [pscustomobject]@{
            Process = $p.ProcessName; PID = $p.Id; Origine = (Get-Origin $path)
            'CPU %' = $cpu; 'RAM MB' = [math]::Round($p.WorkingSet64 / 1MB, 0); Threads = $p.Threads.Count
            Handles = $p.HandleCount; Services = $s; Chemin = $path
        }
    }
    Write-Host "`n[Resume par origine]" -ForegroundColor Green
    $rows | Group-Object Origine | ForEach-Object {
        [pscustomobject]@{ Origine = $_.Name; Processus = $_.Count; 'RAM MB' = ($_.Group | Measure-Object 'RAM MB' -Sum).Sum; 'CPU %' = [math]::Round(($_.Group | Measure-Object 'CPU %' -Sum).Sum, 1) }
    } | Sort-Object 'RAM MB' -Descending | Format-Table -AutoSize

    Write-Host "[Top 20 CPU]" -ForegroundColor Green
    $rows | Sort-Object 'CPU %' -Descending | Select-Object -First 20 Process, PID, Origine, 'CPU %', 'RAM MB', Services | Format-Table -AutoSize
    Write-Host "[Top 20 RAM]" -ForegroundColor Green
    $rows | Sort-Object 'RAM MB' -Descending | Select-Object -First 20 Process, PID, Origine, 'CPU %', 'RAM MB' | Format-Table -AutoSize
    Write-Host "[Processus NON natifs]" -ForegroundColor Green
    $rows | Where-Object { -not (Test-IsNative $_.Origine) -and $_.Origine -ne 'Systeme/Inconnu' } | Sort-Object 'RAM MB' -Descending |
        Select-Object Process, PID, Origine, 'CPU %', 'RAM MB', Chemin | Format-Table -AutoSize
    Save-Csv ($rows | Sort-Object 'RAM MB' -Descending) 'processes'
}

# ---------------------------------------------------------------- 3. APPLICATIONS
function Get-ServiceExe([string]$pathName) {
    if ($pathName -match '^\s*"([^"]+)"') { return $Matches[1] }
    if ($pathName -match '^\s*(\S+?\.exe)') { return $Matches[1] }
    return $null
}

function Invoke-AppScan {
    Show-Header "APPLICATIONS"
    # Appx / Store
    $appx = Get-AppxPackage -AllUsers | Where-Object { -not $_.IsFramework } | ForEach-Object {
        $nat = 'Pas natif'
        if ($_.SignatureKind -eq 'System') { $nat = 'Natif (inbox)' }
        [pscustomobject]@{ Nom = $_.Name; Version = $_.Version; Editeur = ($_.Publisher -replace '^CN=([^,]+).*', '$1'); Type = 'Appx'; Natif = $nat; NonRemovable = $_.NonRemovable }
    } | Sort-Object Natif, Nom -Unique
    # Win32
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $win32 = Get-ItemProperty $keys | Where-Object { $_.DisplayName -and -not $_.SystemComponent } | ForEach-Object {
        $nat = 'Pas natif'; if ($_.Publisher -match 'Microsoft') { $nat = 'Microsoft (hors OS)' }
        [pscustomobject]@{ Nom = $_.DisplayName; Version = $_.DisplayVersion; Editeur = $_.Publisher; Type = 'Win32'; Natif = $nat; NonRemovable = $false }
    } | Sort-Object Nom -Unique
    $all = @($appx) + @($win32)
    Write-Host "`n[Resume]" -ForegroundColor Green
    $all | Group-Object Type, Natif | Select-Object @{n='Categorie';e={$_.Name}}, Count | Format-Table -AutoSize
    Write-Host "[Applications NON natives]" -ForegroundColor Green
    $all | Where-Object { $_.Natif -ne 'Natif (inbox)' } | Select-Object Nom, Version, Editeur, Type, Natif | Format-Table -AutoSize
    Save-Csv $all 'apps'

    # Services tiers
    $svcs = Get-CimInstance Win32_Service | ForEach-Object {
        $exe = Get-ServiceExe $_.PathName
        [pscustomobject]@{ Service = $_.Name; Affichage = $_.DisplayName; Etat = $_.State; Demarrage = $_.StartMode; Origine = (Get-Origin $exe); Chemin = $exe }
    }
    Write-Host "[Services NON natifs]" -ForegroundColor Green
    $svcs | Where-Object { -not (Test-IsNative $_.Origine) } | Sort-Object Etat | Select-Object Service, Affichage, Etat, Demarrage, Origine | Format-Table -AutoSize
    Save-Csv $svcs 'services'

    # Taches planifiees tierces
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\Windows\*' } | ForEach-Object {
        [pscustomobject]@{ Tache = $_.TaskName; Chemin = $_.TaskPath; Etat = $_.State; Action = (($_.Actions | ForEach-Object { $_.Execute }) -join ' ') }
    }
    Write-Host "[Taches planifiees hors \Microsoft\Windows]" -ForegroundColor Green
    $tasks | Format-Table -AutoSize
    Save-Csv $tasks 'tasks'

    # Demarrage
    $start = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
    Write-Host "[Elements de demarrage]" -ForegroundColor Green
    $start | Format-Table -AutoSize -Wrap
    Save-Csv $start 'startup'
}

# ---------------------------------------------------------------- 4. CLEANUP (dry-run par defaut, reversible)
$Cleanup_Services = @(   # service, raison
    @('DiagTrack','Telemetrie (Connected User Experiences)'),
    @('dmwappushservice','WAP push / telemetrie'),
    @('MapsBroker','Cartes hors-ligne'),
    @('RetailDemo','Mode demo magasin'),
    @('Fax','Fax'),
    @('RemoteRegistry','Registre distant'),
    @('lfsvc','Geolocalisation'),
    @('WerSvc','Rapport d''erreurs Windows'),
    @('XblAuthManager','Xbox Live Auth'),
    @('XblGameSave','Xbox Live sauvegardes'),
    @('XboxNetApiSvc','Xbox Live reseau'),
    @('XboxGipSvc','Xbox accessoires'),
    @('WMPNetworkSvc','Partage Windows Media Player')
)

$Cleanup_Tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
)

$Cleanup_Registry = @(   # chemin, nom, valeur, description
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','AllowTelemetry',0,'Telemetrie minimale (0 = Entreprise, sinon 1 en Home/Pro)'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','DoNotShowFeedbackNotifications',1,'Pas de notifications feedback'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent','DisableWindowsConsumerFeatures',1,'Pas d''apps/pubs suggerees'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo','DisabledByGroupPolicy',1,'ID publicitaire desactive'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','PublishUserActivities',0,'Pas de timeline/activites'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','UploadUserActivities',0,'Pas d''upload d''activites'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','EnableActivityFeed',0,'Activity feed desactive'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting','Disabled',1,'Rapport d''erreurs desactive')
)

function Confirm-Step($msg) {
    $r = Read-Host "$msg (O/N)"
    return ($r -match '^[oOyY]')
}

function Invoke-Cleanup {
    param([switch]$DoApply)
    if ($DoApply -and -not $script:IsAdmin) { Write-Host "Le mode -Apply exige une console administrateur." -ForegroundColor Red; return }
    $title = 'CLEANUP - DRY-RUN (aucune modification)'; if ($DoApply) { $title = 'CLEANUP - APPLICATION' }
    Show-Header $title
    Write-Host "  Windows Update (wuauserv, UsoSvc, BITS, DoSvc, WaaSMedicSvc, CryptSvc, TrustedInstaller...) : jamais touche." -ForegroundColor Green

    $undo = New-Object System.Collections.ArrayList

    # --- A. Services Windows inutiles
    $svcPlan = foreach ($s in $Cleanup_Services) {
        if ($s[0] -in $Protected_Services) { continue }
        $o = Get-CimInstance Win32_Service -Filter "Name='$($s[0])'"
        if ($o -and $o.StartMode -ne 'Disabled') { [pscustomobject]@{ Service = $s[0]; Etat = $o.State; Demarrage = $o.StartMode; Raison = $s[1] } }
    }
    Write-Host "`n[A] Services Windows a desactiver : $(@($svcPlan).Count)" -ForegroundColor Green
    $svcPlan | Format-Table -AutoSize

    # --- B. Taches de telemetrie
    $taskPlan = foreach ($t in $Cleanup_Tasks) {
        $name = Split-Path $t -Leaf; $path = (Split-Path $t -Parent) + '\'
        $o = Get-ScheduledTask -TaskPath $path -TaskName $name
        if ($o -and $o.State -ne 'Disabled') { [pscustomobject]@{ Tache = $t; Etat = $o.State } }
    }
    Write-Host "[B] Taches de telemetrie a desactiver : $(@($taskPlan).Count)" -ForegroundColor Green
    $taskPlan | Format-Table -AutoSize

    # --- C. Registre / politiques
    $regPlan = foreach ($r in $Cleanup_Registry) {
        $cur = (Get-ItemProperty -Path $r[0] -Name $r[1]).($r[1])
        if ($cur -ne $r[2]) { [pscustomobject]@{ Cle = $r[0]; Nom = $r[1]; Actuel = $cur; Cible = $r[2]; Effet = $r[3] } }
    }
    Write-Host "[C] Politiques registre a poser : $(@($regPlan).Count)" -ForegroundColor Green
    $regPlan | Format-Table -AutoSize -Wrap

    # --- D. Services tiers (selection manuelle)
    $tp = Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.Name -notin $Protected_Services } | ForEach-Object {
        $exe = Get-ServiceExe $_.PathName; $o = Get-Origin $exe
        if (-not (Test-IsNative $o)) { [pscustomobject]@{ Service = $_.Name; Affichage = $_.DisplayName; Etat = $_.State; Origine = $o } }
    }
    $tp = @($tp); for ($i = 0; $i -lt $tp.Count; $i++) { $tp[$i] | Add-Member -NotePropertyName '#' -NotePropertyValue ($i + 1) }
    Write-Host "[D] Services tiers en demarrage auto (selection manuelle) : $($tp.Count)" -ForegroundColor Green
    $tp | Select-Object '#', Service, Affichage, Etat, Origine | Format-Table -AutoSize

    # --- E. Firewall : blocage sortant des exe tiers vus dans le scan reseau
    $fwCand = @($script:LastNet | Where-Object { $_.Chemin -and -not (Test-IsNative $_.Origine) -and $_.Process -notin $WU_Processes })
    for ($i = 0; $i -lt $fwCand.Count; $i++) { $fwCand[$i] | Add-Member -NotePropertyName '#' -NotePropertyValue ($i + 1) -Force }
    Write-Host "[E] Executables tiers avec flux sortants (dernier scan reseau) : $($fwCand.Count)" -ForegroundColor Green
    if ($fwCand.Count -eq 0) { Write-Host "    (lancer d'abord le scan reseau pour alimenter cette liste)" -ForegroundColor DarkGray }
    else { $fwCand | Select-Object '#', Process, Origine, Destinations, Chemin | Format-Table -AutoSize -Wrap }

    if (-not $DoApply) {
        Write-Host "`nDry-run termine. Relancer avec -Apply pour appliquer. Annulation : -Mode Rollback." -ForegroundColor Yellow
        return
    }

    # ---------- APPLY
    $rp = $false
    try { Checkpoint-Computer -Description "WinOpt $script:Stamp" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; $rp = $true } catch {}
    if ($rp) { Write-Host "Point de restauration cree." -ForegroundColor Green }
    else { Write-Host "Point de restauration impossible (desactive ou deja cree < 24h) - le fichier undo reste disponible." -ForegroundColor Yellow }

    if (@($svcPlan).Count -gt 0 -and (Confirm-Step "Appliquer [A] services")) {
        foreach ($s in $svcPlan) {
            $mode = $s.Demarrage; if ($mode -eq 'Auto') { $mode = 'Automatic' }
            [void]$undo.Add(@{ type = 'service'; name = $s.Service; old = $mode })
            Stop-Service -Name $s.Service -Force
            Set-Service -Name $s.Service -StartupType Disabled
            Write-Host "  service desactive : $($s.Service)"
        }
    }
    if (@($taskPlan).Count -gt 0 -and (Confirm-Step "Appliquer [B] taches")) {
        foreach ($t in $taskPlan) {
            $name = Split-Path $t.Tache -Leaf; $path = (Split-Path $t.Tache -Parent) + '\'
            [void]$undo.Add(@{ type = 'task'; path = $path; name = $name })
            Disable-ScheduledTask -TaskPath $path -TaskName $name | Out-Null
            Write-Host "  tache desactivee : $($t.Tache)"
        }
    }
    if (@($regPlan).Count -gt 0 -and (Confirm-Step "Appliquer [C] registre")) {
        foreach ($r in $regPlan) {
            if (-not (Test-Path $r.Cle)) { New-Item -Path $r.Cle -Force | Out-Null }
            $hadOld = $null -ne $r.Actuel
            [void]$undo.Add(@{ type = 'reg'; key = $r.Cle; name = $r.Nom; had = $hadOld; old = $r.Actuel })
            Set-ItemProperty -Path $r.Cle -Name $r.Nom -Value $r.Cible -Type DWord
            Write-Host "  registre : $($r.Nom) = $($r.Cible)"
        }
    }
    if ($tp.Count -gt 0) {
        $sel = Read-Host "[D] Numeros de services tiers a desactiver (ex: 1,4,7 ; vide = aucun)"
        foreach ($n in ($sel -split '[,\s]+' | Where-Object { $_ -match '^\d+$' })) {
            $x = $tp | Where-Object { $_.'#' -eq [int]$n }
            if ($x) {
                [void]$undo.Add(@{ type = 'service'; name = $x.Service; old = 'Automatic' })
                Stop-Service -Name $x.Service -Force
                Set-Service -Name $x.Service -StartupType Disabled
                Write-Host "  service tiers desactive : $($x.Service)"
            }
        }
    }
    if ($fwCand.Count -gt 0) {
        $sel = Read-Host "[E] Numeros d'executables dont bloquer le SORTANT (ex: 2,5 ; vide = aucun)"
        foreach ($n in ($sel -split '[,\s]+' | Where-Object { $_ -match '^\d+$' })) {
            $x = $fwCand | Where-Object { $_.'#' -eq [int]$n }
            if ($x -and (Test-Path $x.Chemin)) {
                $rn = "WinOpt Block $($x.Process) ($($x.Chemin))"
                New-NetFirewallRule -DisplayName $rn -Group 'WinOpt' -Direction Outbound -Program $x.Chemin -Action Block -Profile Any | Out-Null
                [void]$undo.Add(@{ type = 'fw'; name = $rn })
                Write-Host "  sortant bloque : $($x.Process)"
            }
        }
    }
    $f = Join-Path $OutDir "undo_$script:Stamp.json"
    ConvertTo-Json -InputObject @($undo) -Depth 4 | Set-Content -Path $f -Encoding UTF8
    Write-Host "`nFichier d'annulation : $f  (-Mode Rollback)" -ForegroundColor Green
}

function Invoke-Rollback {
    Show-Header "ROLLBACK"
    if (-not $script:IsAdmin) { Write-Host "Console administrateur requise." -ForegroundColor Red; return }
    $f = Get-ChildItem $OutDir -Filter 'undo_*.json' | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $f) { Write-Host "Aucun fichier undo dans $OutDir"; return }
    Write-Host "Fichier : $($f.FullName)"
    if (-not (Confirm-Step "Annuler ces changements")) { return }
    $items = Get-Content $f.FullName -Raw | ConvertFrom-Json
    foreach ($i in $items) {
        switch ($i.type) {
            'service' { Set-Service -Name $i.name -StartupType $i.old; if ($i.old -eq 'Automatic') { Start-Service -Name $i.name }; Write-Host "  service restaure : $($i.name) -> $($i.old)" }
            'task'    { Enable-ScheduledTask -TaskPath $i.path -TaskName $i.name | Out-Null; Write-Host "  tache reactivee : $($i.path)$($i.name)" }
            'reg'     { if ($i.had) { Set-ItemProperty -Path $i.key -Name $i.name -Value $i.old } else { Remove-ItemProperty -Path $i.key -Name $i.name }; Write-Host "  registre restaure : $($i.name)" }
            'fw'      { Remove-NetFirewallRule -DisplayName $i.name; Write-Host "  regle supprimee : $($i.name)" }
        }
    }
    Write-Host "Rollback termine." -ForegroundColor Green
}

# ---------------------------------------------------------------- MENU
function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "================ WinOpt ================" -ForegroundColor Cyan
        $a = 'NON (limite)'; if ($script:IsAdmin) { $a = 'oui' }
        Write-Host " Admin : $a   |   Exports : $OutDir"
        Write-Host " 1. Flux reseau (entrant/sortant, par carte et par processus)"
        Write-Host " 2. Processus (natifs / non natifs, CPU, RAM)"
        Write-Host " 3. Applications, services, taches, demarrage (natif / pas natif)"
        Write-Host " 4. Cleanup - DRY-RUN"
        Write-Host " 5. Cleanup - APPLIQUER"
        Write-Host " 6. Rollback du dernier cleanup"
        Write-Host " 7. Tout (1+2+3)"
        Write-Host " 0. Quitter"
        $c = Read-Host 'Choix'
        switch ($c) {
            '1' { $s = Read-Host "Duree de capture en secondes [$Seconds]"; if ($s -match '^\d+$') { $script:Seconds = [int]$s }; Invoke-NetScan -Sec $Seconds }
            '2' { Invoke-ProcScan }
            '3' { Invoke-AppScan }
            '4' { Invoke-Cleanup }
            '5' { Invoke-Cleanup -DoApply }
            '6' { Invoke-Rollback }
            '7' { Invoke-NetScan -Sec $Seconds; Invoke-ProcScan; Invoke-AppScan }
            '0' { return }
        }
    }
}

switch ($Mode) {
    'Menu'      { Show-Menu }
    'Network'   { Invoke-NetScan -Sec $Seconds }
    'Processes' { Invoke-ProcScan }
    'Apps'      { Invoke-AppScan }
    'Cleanup'   { if ($Apply) { Invoke-NetScan -Sec ([math]::Min($Seconds,15)); Invoke-Cleanup -DoApply } else { Invoke-NetScan -Sec ([math]::Min($Seconds,15)); Invoke-Cleanup } }
    'Rollback'  { Invoke-Rollback }
    'All'       { Invoke-NetScan -Sec $Seconds; Invoke-ProcScan; Invoke-AppScan }
}