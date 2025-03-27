# Gestionnaire ASP.NET Core avec intégration Artifactory
# Ce script permet de gérer les installations et suppressions des versions ASP.NET Core
# en utilisant un dépôt Artifactory d'entreprise comme source des packages

param (
    [Parameter(Mandatory=$false)]
    [string]$Action = "help",
    
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$ArtifactoryUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$Repository,
    
    [Parameter(Mandatory=$false)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiToken,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
    
    # Nous retirons le paramètre Verbose personnalisé car c'est un paramètre commun PowerShell
)

# Fonction pour afficher l'aide
function Show-Help {
    Write-Host "Script de gestion des versions ASP.NET Core avec Artifactory" -ForegroundColor Green
    Write-Host "-------------------------------------------------------" -ForegroundColor Green
    Write-Host "Utilisation:" -ForegroundColor Yellow
    Write-Host "  .\ASPNetCoreManager.ps1 -Action <action> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions disponibles:" -ForegroundColor Yellow
    Write-Host "  list        : Liste toutes les versions installées"
    Write-Host "  listremote  : Liste toutes les versions disponibles dans Artifactory"
    Write-Host "  install     : Installe une version spécifique depuis Artifactory (requiert -Version)"
    Write-Host "  uninstall   : Désinstalle une version spécifique (requiert -Version)"
    Write-Host "  setup       : Configure les informations de connexion à Artifactory"
    Write-Host "  help        : Affiche cette aide"
    Write-Host ""
    Write-Host "Options d'Artifactory:" -ForegroundColor Yellow
    Write-Host "  -ArtifactoryUrl : URL du serveur Artifactory"
    Write-Host "  -Repository     : Nom du dépôt Artifactory"
    Write-Host "  -Username       : Nom d'utilisateur pour l'authentification"
    Write-Host "  -Password       : Mot de passe pour l'authentification"
    Write-Host "  -ApiToken       : Token API pour l'authentification (alternative à Username/Password)"
    Write-Host ""
    Write-Host "Exemples:" -ForegroundColor Cyan
    Write-Host "  .\ASPNetCoreManager.ps1 -Action setup -ArtifactoryUrl https://artifactory.entreprise.com -Repository dotnet-repo -Username user -Password pass"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action listremote"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action install -Version 6.0.19"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action uninstall -Version 5.0.17 -Force"
}

# Fonction pour afficher les messages détaillés
function Write-VerboseMessage {
    param (
        [string]$Message
    )
    
    # Utilisation de $VerbosePreference au lieu de $Verbose
    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose $Message
    }
}

# Fonction pour charger la configuration
function Load-Configuration {
    $configPath = "$env:USERPROFILE\.dotnet-artifactory-config.xml"
    
    if (Test-Path -Path $configPath) {
        try {
            $config = Import-Clixml -Path $configPath
            return $config
        } catch {
            Write-Host "Erreur lors du chargement de la configuration: $_" -ForegroundColor Red
            return $null
        }
    } else {
        Write-Host "Aucune configuration trouvée. Veuillez exécuter d'abord l'action 'setup'." -ForegroundColor Yellow
        return $null
    }
}

# Fonction pour sauvegarder la configuration
function Save-Configuration {
    param (
        [string]$ArtifactoryUrl,
        [string]$Repository,
        [string]$Username,
        [string]$Password,
        [string]$ApiToken
    )
    
    $configPath = "$env:USERPROFILE\.dotnet-artifactory-config.xml"
    
    $config = @{
        ArtifactoryUrl = $ArtifactoryUrl
        Repository = $Repository
        Username = $Username
        Password = $Password
        ApiToken = $ApiToken
        LastUpdated = Get-Date
    }
    
    try {
        $config | Export-Clixml -Path $configPath -Force
        Write-Host "Configuration sauvegardée avec succès." -ForegroundColor Green
    } catch {
        Write-Host "Erreur lors de la sauvegarde de la configuration: $_" -ForegroundColor Red
    }
}

# Fonction pour configurer Artifactory
function Setup-Artifactory {
    param (
        [string]$ArtifactoryUrl,
        [string]$Repository,
        [string]$Username,
        [string]$Password,
        [string]$ApiToken
    )
    
    if ([string]::IsNullOrEmpty($ArtifactoryUrl)) {
        $ArtifactoryUrl = Read-Host "Entrez l'URL du serveur Artifactory"
    }
    
    if ([string]::IsNullOrEmpty($Repository)) {
        $Repository = Read-Host "Entrez le nom du dépôt Artifactory"
    }
    
    # Si ni ApiToken ni les identifiants ne sont fournis, demander à l'utilisateur sa méthode préférée
    if ([string]::IsNullOrEmpty($ApiToken) -and ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password))) {
        $authMethod = Read-Host "Méthode d'authentification (1 pour Utilisateur/Mot de passe, 2 pour Token API)"
        
        if ($authMethod -eq "1") {
            if ([string]::IsNullOrEmpty($Username)) {
                $Username = Read-Host "Entrez votre nom d'utilisateur"
            }
            
            if ([string]::IsNullOrEmpty($Password)) {
                $securePassword = Read-Host "Entrez votre mot de passe" -AsSecureString
                $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
            }
            
            $ApiToken = ""
        } else {
            if ([string]::IsNullOrEmpty($ApiToken)) {
                $secureToken = Read-Host "Entrez votre token API" -AsSecureString
                $ApiToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
            }
            
            $Username = ""
            $Password = ""
        }
    }
    
    Save-Configuration -ArtifactoryUrl $ArtifactoryUrl -Repository $Repository -Username $Username -Password $Password -ApiToken $ApiToken
    
    # Tester la connexion
    Write-Host "Test de la connexion à Artifactory..." -ForegroundColor Yellow
    
    $headers = @{}
    
    if (-not [string]::IsNullOrEmpty($ApiToken)) {
        $headers.Add("X-JFrog-Art-Api", $ApiToken)
    } else {
        $credPair = "$($Username):$($Password)"
        $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
        $headers.Add("Authorization", "Basic $encodedCredentials")
    }
    
    try {
        $testUrl = "$ArtifactoryUrl/api/system/ping"
        $response = Invoke-WebRequest -Uri $testUrl -Headers $headers -UseBasicParsing
        
        if ($response.StatusCode -eq 200) {
            Write-Host "Connexion réussie à Artifactory!" -ForegroundColor Green
        } else {
            Write-Host "La connexion a échoué. Code de statut: $($response.StatusCode)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Erreur lors du test de connexion: $_" -ForegroundColor Red
    }
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

# Fonction pour lister les versions disponibles dans Artifactory
function List-RemoteVersions {
    $config = Load-Configuration
    
    if (-not $config) {
        return
    }
    
    Write-Host "Récupération des versions ASP.NET Core disponibles dans Artifactory..." -ForegroundColor Green
    
    $headers = @{}
    
    if (-not [string]::IsNullOrEmpty($config.ApiToken)) {
        $headers.Add("X-JFrog-Art-Api", $config.ApiToken)
    } else {
        $credPair = "$($config.Username):$($config.Password)"
        $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
        $headers.Add("Authorization", "Basic $encodedCredentials")
    }
    
    try {
        # URL de l'API Artifactory pour rechercher les packages
        $searchUrl = "$($config.ArtifactoryUrl)/api/search/pattern?pattern=$($config.Repository):dotnet-sdk/*"
        
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -UseBasicParsing
        
        if ($response.files.Count -eq 0) {
            Write-Host "Aucune version trouvée dans le dépôt Artifactory." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Versions SDK .NET disponibles dans Artifactory:" -ForegroundColor Green
        Write-Host "---------------------------------------" -ForegroundColor Green
        
        # Extraire les versions des noms de fichiers
        $versions = @()
        
        foreach ($file in $response.files) {
            if ($file -match "dotnet-sdk-(.+)-win") {
                $versions += $matches[1]
            }
        }
        
        # Grouper par version majeure
        $versionGroups = $versions | Group-Object { $_.Split('.')[0] }
        
        foreach ($group in $versionGroups) {
            Write-Host "SDK .NET $($group.Name).x:" -ForegroundColor Cyan
            
            $sortedVersions = $group.Group | Sort-Object { [version]$_ }
            
            foreach ($version in $sortedVersions) {
                Write-Host "  - $version" -ForegroundColor Yellow
            }
            
            Write-Host ""
        }
    } catch {
        Write-Host "Erreur lors de la récupération des versions disponibles dans Artifactory: $_" -ForegroundColor Red
    }
}

# Fonction pour télécharger un package depuis Artifactory
function Download-Package {
    param (
        [string]$PackagePath,
        [string]$OutputPath = "$env:TEMP\dotnet-downloads"
    )
    
    $config = Load-Configuration
    
    if (-not $config) {
        return $null
    }
    
    # Créer le répertoire de sortie s'il n'existe pas
    if (-not (Test-Path -Path $OutputPath)) {
        Write-VerboseMessage "Création du répertoire de sortie: $OutputPath"
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Construire l'URL complète
    $fullUrl = "$($config.ArtifactoryUrl)/$($config.Repository)/$PackagePath"
    Write-VerboseMessage "URL de téléchargement: $fullUrl"
    
    # Préparer les en-têtes pour l'authentification
    $headers = @{}
    
    if (-not [string]::IsNullOrEmpty($config.ApiToken)) {
        Write-VerboseMessage "Utilisation de l'authentification par token API"
        $headers.Add("X-JFrog-Art-Api", $config.ApiToken)
    } else {
        Write-VerboseMessage "Utilisation de l'authentification par nom d'utilisateur/mot de passe"
        $credPair = "$($config.Username):$($config.Password)"
        $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
        $headers.Add("Authorization", "Basic $encodedCredentials")
    }
    
    # Obtenir le nom du fichier à partir du chemin
    $fileName = Split-Path -Path $PackagePath -Leaf
    $outputFilePath = Join-Path -Path $OutputPath -ChildPath $fileName
    
    try {
        Write-Host "Téléchargement du package depuis Artifactory..." -ForegroundColor Green
        
        # Télécharger le fichier
        $progressPreference = 'SilentlyContinue'  # Désactiver la barre de progression pour améliorer les performances
        Invoke-WebRequest -Uri $fullUrl -Headers $headers -OutFile $outputFilePath -UseBasicParsing
        $progressPreference = 'Continue'  # Réactiver la barre de progression
        
        # Vérifier que le fichier a été téléchargé avec succès
        if (Test-Path -Path $outputFilePath) {
            $fileSize = (Get-Item -Path $outputFilePath).Length
            $fileSizeFormatted = "{0:N2} MB" -f ($fileSize / 1MB)
            Write-Host "Téléchargement réussi: $outputFilePath ($fileSizeFormatted)" -ForegroundColor Green
            
            return $outputFilePath
        } else {
            Write-Host "Erreur: Le fichier n'a pas été téléchargé." -ForegroundColor Red
            return $null
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "Erreur d'authentification (code $statusCode): Vérifiez vos identifiants ou votre token." -ForegroundColor Red
        } elseif ($statusCode -eq 404) {
            Write-Host "Erreur 404: Le package n'a pas été trouvé. Vérifiez l'URL et le chemin du package." -ForegroundColor Red
        } else {
            Write-Host "Erreur lors du téléchargement: $_" -ForegroundColor Red
        }
        
        return $null
    }
}

# Fonction pour installer une version spécifique depuis Artifactory
function Install-Version {
    param (
        [string]$Version
    )
    
    if ([string]::IsNullOrEmpty($Version)) {
        Write-Host "Vous devez spécifier une version à installer avec le paramètre -Version" -ForegroundColor Red
        return
    }
    
    Write-Host "Installation de ASP.NET Core SDK version $Version depuis Artifactory..." -ForegroundColor Green
    
    try {
        # Vérification si la version est déjà installée
        $installedSdks = dotnet --list-sdks
        $isInstalled = $installedSdks | Where-Object { $_ -like "$Version*" }
        
        if ($isInstalled) {
            Write-Host "La version $Version est déjà installée." -ForegroundColor Yellow
            return
        }
        
        # Télécharger le SDK depuis Artifactory
        $sdkPackagePath = "dotnet-sdk/dotnet-sdk-$Version-win-x64.exe"
        $sdkInstallerPath = Download-Package -PackagePath $sdkPackagePath
        
        if (-not $sdkInstallerPath) {
            Write-Host "Impossible de télécharger le SDK .NET $Version." -ForegroundColor Red
            return
        }
        
        # Installer le SDK
        Write-Host "Installation du SDK .NET $Version..." -ForegroundColor Yellow
        $installProcess = Start-Process -FilePath $sdkInstallerPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
        
        if ($installProcess.ExitCode -ne 0) {
            Write-Host "Erreur lors de l'installation du SDK .NET $Version. Code de sortie: $($installProcess.ExitCode)" -ForegroundColor Red
            return
        }
        
        # Télécharger le runtime ASP.NET Core si disponible
        $aspNetPackagePath = "dotnet-runtime/aspnetcore-runtime-$Version-win-x64.exe"
        $aspNetInstallerPath = Download-Package -PackagePath $aspNetPackagePath
        
        if ($aspNetInstallerPath) {
            Write-Host "Installation du runtime ASP.NET Core $Version..." -ForegroundColor Yellow
            $runtimeProcess = Start-Process -FilePath $aspNetInstallerPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
            
            if ($runtimeProcess.ExitCode -ne 0) {
                Write-Host "Avertissement: L'installation du runtime ASP.NET Core a échoué. Code de sortie: $($runtimeProcess.ExitCode)" -ForegroundColor Yellow
            }
        }
        
        Write-Host "Installation de ASP.NET Core $Version terminée avec succès!" -ForegroundColor Green
        Write-Host "Veuillez redémarrer votre terminal pour que les changements prennent effet." -ForegroundColor Cyan
        
        # Nettoyage des fichiers temporaires
        if (Test-Path $sdkInstallerPath) {
            Remove-Item $sdkInstallerPath -Force
        }
        
        if ($aspNetInstallerPath -and (Test-Path $aspNetInstallerPath)) {
            Remove-Item $aspNetInstallerPath -Force
        }
    } catch {
        Write-Host "Erreur lors de l'installation de la version $Version : $_" -ForegroundColor Red
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
    "setup" {
        Setup-Artifactory -ArtifactoryUrl $ArtifactoryUrl -Repository $Repository -Username $Username -Password $Password -ApiToken $ApiToken
    }
    default {
        Show-Help
    }
}
