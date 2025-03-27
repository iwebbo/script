# ASP.NET Core Version Manager
# Ce script permet de gérer les installations et suppressions des versions ASP.NET Core sur Windows
# Il offre des fonctionnalités pour lister, installer, et désinstaller différentes versions

param (
    [Parameter(Mandatory=$false)]
    [string]$Action = "help",
    
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
)

# Fonction pour afficher l'aide
function Show-Help {
    Write-Host "Script de gestion des versions ASP.NET Core" -ForegroundColor Green
    Write-Host "---------------------------------------" -ForegroundColor Green
    Write-Host "Utilisation:" -ForegroundColor Yellow
    Write-Host "  .\ASPNetCoreManager.ps1 -Action <action> -Version <version> [-Force]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions disponibles:" -ForegroundColor Yellow
    Write-Host "  list        : Liste toutes les versions installées"
    Write-Host "  listremote  : Liste toutes les versions disponibles en ligne"
    Write-Host "  install     : Installe une version spécifique (requiert -Version)"
    Write-Host "  uninstall   : Désinstalle une version spécifique (requiert -Version)"
    Write-Host "  help        : Affiche cette aide"
    Write-Host ""
    Write-Host "Exemples:" -ForegroundColor Cyan
    Write-Host "  .\ASPNetCoreManager.ps1 -Action list"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action install -Version 6.0.19"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action uninstall -Version 5.0.17 -Force"
}

# Fonction pour lister les versions installées
function List-InstalledVersions {
    Write-Host "Versions ASP.NET Core installées:" -ForegroundColor Green
    Write-Host "---------------------------------------" -ForegroundColor Green
    
    try {
        $dotnetInfo = dotnet --list-sdks
        
        if ($dotnetInfo.Count -eq 0) {
            Write-Host "Aucune version SDK .NET n'est installée." -ForegroundColor Yellow
        } else {
            foreach ($line in $dotnetInfo) {
                $version = $line.Split(" ")[0]
                $path = $line.Split(" ")[1].Trim("[", "]")
                Write-Host "Version: $version" -ForegroundColor Cyan
                Write-Host "Chemin: $path" -ForegroundColor Gray
                Write-Host ""
            }
        }
        
        Write-Host "Runtimes ASP.NET Core installés:" -ForegroundColor Green
        Write-Host "---------------------------------------" -ForegroundColor Green
        
        $dotnetRuntimes = dotnet --list-runtimes | Where-Object { $_ -like "Microsoft.AspNetCore.App*" }
        
        if ($dotnetRuntimes.Count -eq 0) {
            Write-Host "Aucun runtime ASP.NET Core n'est installé." -ForegroundColor Yellow
        } else {
            foreach ($line in $dotnetRuntimes) {
                $parts = $line.Split(" ")
                $version = $parts[1]
                $path = $parts[2].Trim("[", "]")
                Write-Host "Version: $version" -ForegroundColor Cyan
                Write-Host "Chemin: $path" -ForegroundColor Gray
                Write-Host ""
            }
        }
    } catch {
        Write-Host "Erreur lors de la récupération des versions installées: $_" -ForegroundColor Red
    }
}

# Fonction pour lister les versions disponibles en ligne
function List-RemoteVersions {
    Write-Host "Récupération des versions ASP.NET Core disponibles en ligne..." -ForegroundColor Green
    
    try {
        $releases = Invoke-RestMethod -Uri "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"
        
        Write-Host "Versions SDK .NET disponibles:" -ForegroundColor Green
        Write-Host "---------------------------------------" -ForegroundColor Green
        
        foreach ($release in $releases.releases.PSObject.Properties) {
            $channel = $release.Value."channel-version"
            $latestRelease = $release.Value."latest-release"
            $releaseDate = $release.Value."release-date"
            $support = $release.Value."support-phase"
            
            Write-Host "Channel: $channel" -ForegroundColor Cyan
            Write-Host "Dernière version: $latestRelease" -ForegroundColor Yellow
            Write-Host "Date de sortie: $releaseDate" -ForegroundColor Gray
            Write-Host "Phase de support: $support" -ForegroundColor Gray
            Write-Host ""
        }
    } catch {
        Write-Host "Erreur lors de la récupération des versions disponibles: $_" -ForegroundColor Red
    }
}

# Fonction pour installer une version spécifique
function Install-Version {
    param (
        [string]$Version
    )
    
    if ([string]::IsNullOrEmpty($Version)) {
        Write-Host "Vous devez spécifier une version à installer avec le paramètre -Version" -ForegroundColor Red
        return
    }
    
    Write-Host "Installation de ASP.NET Core SDK version $Version..." -ForegroundColor Green
    
    try {
        # Vérification si la version est déjà installée
        $installedSdks = dotnet --list-sdks
        $isInstalled = $installedSdks | Where-Object { $_ -like "$Version*" }
        
        if ($isInstalled) {
            Write-Host "La version $Version est déjà installée." -ForegroundColor Yellow
            return
        }
        
        # Téléchargement et installation de la version spécifiée
        $majorVersion = $Version.Split('.')[0]
        $dotnetInstallScript = "$env:TEMP\dotnet-install.ps1"
        
        # Téléchargement du script d'installation .NET
        Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $dotnetInstallScript
        
        # Installation du SDK
        Write-Host "Téléchargement et installation du SDK .NET $Version..." -ForegroundColor Yellow
        & $dotnetInstallScript -Version $Version -InstallDir "C:\Program Files\dotnet"
        
        # Installation du runtime ASP.NET Core
        Write-Host "Installation du runtime ASP.NET Core $Version..." -ForegroundColor Yellow
        & $dotnetInstallScript -Version $Version -Runtime aspnetcore -InstallDir "C:\Program Files\dotnet"
        
        Write-Host "Installation de ASP.NET Core $Version terminée avec succès!" -ForegroundColor Green
        Write-Host "Veuillez redémarrer votre terminal pour que les changements prennent effet." -ForegroundColor Cyan
    } catch {
        Write-Host "Erreur lors de l'installation de la version $Version : $_" -ForegroundColor Red
    } finally {
        if (Test-Path $dotnetInstallScript) {
            Remove-Item $dotnetInstallScript -Force
        }
    }
}

# Fonction pour désinstaller une version spécifique
function Uninstall-Version {
    param (
        [string]$Version,
        [bool]$Force
    )
    
    if ([string]::IsNullOrEmpty($Version)) {
        Write-Host "Vous devez spécifier une version à désinstaller avec le paramètre -Version" -ForegroundColor Red
        return
    }
    
    Write-Host "Désinstallation de ASP.NET Core version $Version..." -ForegroundColor Green
    
    try {
        # Vérification si la version est installée
        $installedSdks = dotnet --list-sdks
        $isInstalled = $installedSdks | Where-Object { $_ -like "$Version*" }
        
        if (-not $isInstalled) {
            Write-Host "La version $Version n'est pas installée." -ForegroundColor Yellow
            return
        }
        
        # Confirmation de la désinstallation
        if (-not $Force) {
            $confirmation = Read-Host "Êtes-vous sûr de vouloir désinstaller ASP.NET Core $Version ? (O/N)"
            if ($confirmation -ne "O" -and $confirmation -ne "o") {
                Write-Host "Désinstallation annulée." -ForegroundColor Yellow
                return
            }
        }
        
        # Utilisation de l'outil de désinstallation Windows
        $programName = "Microsoft .NET SDK $Version*"
        $app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like $programName }
        
        if ($app) {
            Write-Host "Désinstallation du SDK .NET $Version..." -ForegroundColor Yellow
            $app.Uninstall() | Out-Null
        } else {
            # Alternative avec PowerShell pour Windows 10/11
            $uninstallPath = Join-Path $env:ProgramFiles "dotnet\shared\Microsoft.AspNetCore.App\$Version"
            if (Test-Path $uninstallPath) {
                Write-Host "Suppression du répertoire: $uninstallPath" -ForegroundColor Yellow
                Remove-Item -Path $uninstallPath -Recurse -Force
            }
            
            $sdkPath = Join-Path $env:ProgramFiles "dotnet\sdk\$Version"
            if (Test-Path $sdkPath) {
                Write-Host "Suppression du répertoire: $sdkPath" -ForegroundColor Yellow
                Remove-Item -Path $sdkPath -Recurse -Force
            }
        }
        
        Write-Host "Désinstallation de ASP.NET Core $Version terminée avec succès!" -ForegroundColor Green
        Write-Host "Veuillez redémarrer votre terminal pour que les changements prennent effet." -ForegroundColor Cyan
    } catch {
        Write-Host "Erreur lors de la désinstallation de la version $Version : $_" -ForegroundColor Red
    }
}

# Exécution principale basée sur l'action spécifiée
switch ($Action.ToLower()) {
    "list" {
        List-InstalledVersions
    }
    "listremote" {
        List-RemoteVersions
    }
    "install" {
        Install-Version -Version $Version
    }
    "uninstall" {
        Uninstall-Version -Version $Version -Force $Force
    }
    default {
        Show-Help
    }
}
