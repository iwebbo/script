# Manage your ASP.NET Core from Artifactory
# Install/Uninstall ASP.NET Core 


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

)

# Function HELP 
function Show-Help {
    Write-Host "Management of ASP.NET Core from Artifactory" -ForegroundColor Green
    Write-Host "-------------------------------------------------------" -ForegroundColor Green
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\ASPNetCoreManager.ps1 -Action <action> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions availables:" -ForegroundColor Yellow
    Write-Host "  list        : List all versions installed"
    Write-Host "  listremote  : List all versions available from Artifactory"
    Write-Host "  install     : Install a version from Artifactory (requiert -Version)"
    Write-Host "  uninstall   : Uninstall a version (requiert -Version)"
    Write-Host "  setup       : Mandatory step, configure your access to Artifactory"
    Write-Host "  help        : Show Help"
    Write-Host ""
    Write-Host "Artifactory setup:" -ForegroundColor Yellow
    Write-Host "  -ArtifactoryUrl : Artifactory Link https://artifactory.example.com"
    Write-Host "  -Repository     : Repository from Artifactory"
    Write-Host "  -Username       : Username of authentification"
    Write-Host "  -Password       : Password of authentification"
    Write-Host "  -ApiToken       : Token API (instead of Username/Password)"
    Write-Host ""
    Write-Host "Exemples:" -ForegroundColor Cyan
    Write-Host "  .\ASPNetCoreManager.ps1 -Action setup -ArtifactoryUrl https://artifactory.example.com -Repository dotnet-repo -Username user -Password pass"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action listremote"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action install -Version 6.0.19"
    Write-Host "  .\ASPNetCoreManager.ps1 -Action uninstall -Version 5.0.17 -Force"
}

# Function show help
function Write-VerboseMessage {
    param (
        [string]$Message
    )
    
    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose $Message
    }
}

# Load configuration of authenfication
function Load-Configuration {
    $configPath = "$env:USERPROFILE\.dotnet-artifactory-config.xml"
    
    if (Test-Path -Path $configPath) {
        try {
            $config = Import-Clixml -Path $configPath
            return $config
        } catch {
            Write-Host "Error with configuration file loading: $_" -ForegroundColor Red
            return $null
        }
    } else {
        Write-Host "Nothing configuration file. Please execute before 'setup'." -ForegroundColor Yellow
        return $null
    }
}

# Function to save a configuration setup Artifactory
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
        Write-Host "Configuration save successfully." -ForegroundColor Green
    } catch {
        Write-Host "Error with saving of configuration: $_" -ForegroundColor Red
    }
}

# Function Setup artifcatory
function Setup-Artifactory {
    param (
        [string]$ArtifactoryUrl,
        [string]$Repository,
        [string]$Username,
        [string]$Password,
        [string]$ApiToken
    )
    
    if ([string]::IsNullOrEmpty($ArtifactoryUrl)) {
        $ArtifactoryUrl = Read-Host "Link of Artifactory"
    }
    
    if ([string]::IsNullOrEmpty($Repository)) {
        $Repository = Read-Host "Repository of Artifactory"
    }
    
    # If nothing user/pass or token has been fill, asking your preference
    if ([string]::IsNullOrEmpty($ApiToken) -and ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password))) {
        $authMethod = Read-Host "Method of authentifcation (1 Username/Password, 2 Token API)"
        
        if ($authMethod -eq "1") {
            if ([string]::IsNullOrEmpty($Username)) {
                $Username = Read-Host "Please enter the username"
            }
            
            if ([string]::IsNullOrEmpty($Password)) {
                $securePassword = Read-Host "Please enter the password" -AsSecureString
                $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
            }
            
            $ApiToken = ""
        } else {
            if ([string]::IsNullOrEmpty($ApiToken)) {
                $secureToken = Read-Host "Please enter the token API" -AsSecureString
                $ApiToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
            }
            
            $Username = ""
            $Password = ""
        }
    }
    
    Save-Configuration -ArtifactoryUrl $ArtifactoryUrl -Repository $Repository -Username $Username -Password $Password -ApiToken $ApiToken
    
    # Tester la connexion
    Write-Host "Check connexion to Artifactory..." -ForegroundColor Yellow
    
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
            Write-Host "Connexion successfully to Artifactory!" -ForegroundColor Green
        } else {
            Write-Host "Connexion failed. Statut code: $($response.StatusCode)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error with testing connexion: $_" -ForegroundColor Red
    }
}

# Fonction pour lister les versions installées
function List-InstalledVersions {
    Write-Host "Versions ASP.NET Core installed:" -ForegroundColor Green
    Write-Host "---------------------------------------" -ForegroundColor Green
    
    try {
        $dotnetInfo = dotnet --list-sdks
        
        if ($dotnetInfo.Count -eq 0) {
            Write-Host "No version SDK .NET detected." -ForegroundColor Yellow
        } else {
            foreach ($line in $dotnetInfo) {
                $version = $line.Split(" ")[0]
                $path = $line.Split(" ")[1].Trim("[", "]")
                Write-Host "Version: $version" -ForegroundColor Cyan
                Write-Host "Path: $path" -ForegroundColor Gray
                Write-Host ""
            }
        }
        
        Write-Host "Runtimes ASP.NET Core Installed:" -ForegroundColor Green
        Write-Host "---------------------------------------" -ForegroundColor Green
        
        $dotnetRuntimes = dotnet --list-runtimes | Where-Object { $_ -like "Microsoft.AspNetCore.App*" }
        
        if ($dotnetRuntimes.Count -eq 0) {
            Write-Host "No runtime ASP.NET Core detected." -ForegroundColor Yellow
        } else {
            foreach ($line in $dotnetRuntimes) {
                $parts = $line.Split(" ")
                $version = $parts[1]
                $path = $parts[2].Trim("[", "]")
                Write-Host "Version: $version" -ForegroundColor Cyan
                Write-Host "Path: $path" -ForegroundColor Gray
                Write-Host ""
            }
        }
    } catch {
        Write-Host "Error with versions installed: $_" -ForegroundColor Red
    }
}

# Fonction pour lister les versions disponibles dans Artifactory
function List-RemoteVersions {
    $config = Load-Configuration
    
    if (-not $config) {
        return
    }
    
    Write-Host "Versions ASP.NET Core available from Artifactory..." -ForegroundColor Green
    
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
            Write-Host "No versions detected from artifactory." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Versions SDK .NET available from artifactory:" -ForegroundColor Green
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
        Write-Host "Error with remotelist: $_" -ForegroundColor Red
    }
}

# Function to download a package from Artifactory
function Download-Package {
    param (
        [string]$PackagePath,
        [string]$OutputPath = "$env:TEMP\dotnet-downloads"
    )
    
    $config = Load-Configuration
    
    if (-not $config) {
        return $null
    }
    
    # Create a folder for download 
    if (-not (Test-Path -Path $OutputPath)) {
        Write-VerboseMessage "Create a download folder: $OutputPath"
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Build link
    $fullUrl = "$($config.ArtifactoryUrl)/$($config.Repository)/$PackagePath"
    Write-VerboseMessage "Link of Download: $fullUrl"
    
    # Head 
    $headers = @{}
    
    if (-not [string]::IsNullOrEmpty($config.ApiToken)) {
        Write-VerboseMessage "Usage from APIToken"
        $headers.Add("X-JFrog-Art-Api", $config.ApiToken)
    } else {
        Write-VerboseMessage "Usage from username & password"
        $credPair = "$($config.Username):$($config.Password)"
        $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
        $headers.Add("Authorization", "Basic $encodedCredentials")
    }
    
    # Get file name 
    $fileName = Split-Path -Path $PackagePath -Leaf
    $outputFilePath = Join-Path -Path $OutputPath -ChildPath $fileName
    
    try {
        Write-Host "Download from Artifactory..." -ForegroundColor Green
        
        # Télécharger le fichier
        $progressPreference = 'SilentlyContinue'  # Deactivate loading
        Invoke-WebRequest -Uri $fullUrl -Headers $headers -OutFile $outputFilePath -UseBasicParsing
        $progressPreference = 'Continue'  # Reactivate loading
        
        # Check if the file has been downloaded
        if (Test-Path -Path $outputFilePath) {
            $fileSize = (Get-Item -Path $outputFilePath).Length
            $fileSizeFormatted = "{0:N2} MB" -f ($fileSize / 1MB)
            Write-Host "Downloaded Successfully: $outputFilePath ($fileSizeFormatted)" -ForegroundColor Green
            
            return $outputFilePath
        } else {
            Write-Host "Error: Download failed." -ForegroundColor Red
            return $null
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "Error authentication (code $statusCode): Please check the token." -ForegroundColor Red
        } elseif ($statusCode -eq 404) {
            Write-Host "Error 404: Please check the package name or the repository name." -ForegroundColor Red
        } else {
            Write-Host "Error of downloading: $_" -ForegroundColor Red
        }
        
        return $null
    }
}

# Function installed version from artifactory 
function Install-Version {
    param (
        [string]$Version
    )
    
    if ([string]::IsNullOrEmpty($Version)) {
        Write-Host "Please push a version number need to be installed -Version" -ForegroundColor Red
        return
    }
    
    Write-Host "Installation of ASP.NET Core SDK version $Version from Artifactory..." -ForegroundColor Green
    
    try {
        # Check if the version is already installed
        $installedSdks = dotnet --list-sdks
        $isInstalled = $installedSdks | Where-Object { $_ -like "$Version*" }
        
        if ($isInstalled) {
            Write-Host "version $Version already installed." -ForegroundColor Yellow
            return
        }
        
        # Downloaded from Artifactory
        $sdkPackagePath = "dotnet-sdk/dotnet-sdk-$Version-win-x64.exe"
        $sdkInstallerPath = Download-Package -PackagePath $sdkPackagePath
        
        if (-not $sdkInstallerPath) {
            Write-Host "Download failed SDK .NET $Version." -ForegroundColor Red
            return
        }
        
        # Installer le SDK
        Write-Host "Installation of SDK .NET $Version..." -ForegroundColor Yellow
        $installProcess = Start-Process -FilePath $sdkInstallerPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
        
        if ($installProcess.ExitCode -ne 0) {
            Write-Host "Issue: Installation failed of SDK .NET $Version. Code: $($installProcess.ExitCode)" -ForegroundColor Red
            return
        }
        
        # Download Runtime if available from Artifactory
        $aspNetPackagePath = "dotnet-runtime/aspnetcore-runtime-$Version-win-x64.exe"
        $aspNetInstallerPath = Download-Package -PackagePath $aspNetPackagePath
        
        if ($aspNetInstallerPath) {
            Write-Host "Installation of runtime ASP.NET Core $Version..." -ForegroundColor Yellow
            $runtimeProcess = Start-Process -FilePath $aspNetInstallerPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
            
            if ($runtimeProcess.ExitCode -ne 0) {
                Write-Host "Issue: Installation failed of runtime ASP.NET Core. Code: $($runtimeProcess.ExitCode)" -ForegroundColor Yellow
            }
        }
        
        Write-Host "Installation of ASP.NET Core $Version successfully !" -ForegroundColor Green
        Write-Host "Please restart the computer." -ForegroundColor Cyan
        
        # Cleanup temp files
        if (Test-Path $sdkInstallerPath) {
            Remove-Item $sdkInstallerPath -Force
        }
        
        if ($aspNetInstallerPath -and (Test-Path $aspNetInstallerPath)) {
            Remove-Item $aspNetInstallerPath -Force
        }
    } catch {
        Write-Host "Error: Installation failed, please check $Version : $_" -ForegroundColor Red
    }
}

# Fonction uninstall a version 
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
