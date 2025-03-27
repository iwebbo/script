# Script de téléchargement de packages depuis Artifactory
# Ce script permet de télécharger des packages .NET depuis un dépôt Artifactory d'entreprise
# en utilisant soit un nom d'utilisateur/mot de passe, soit un token d'authentification

param (
    [Parameter(Mandatory=$true)]
    [string]$ArtifactoryUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$Repository,
    
    [Parameter(Mandatory=$true)]
    [string]$PackagePath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$PWD\downloads",
    
    [Parameter(Mandatory=$false)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiToken
    
    # Nous retirons le paramètre Verbose personnalisé car c'est un paramètre commun PowerShell
)

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

# Vérifier que les paramètres d'authentification sont fournis correctement
if ([string]::IsNullOrEmpty($ApiToken) -and ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password))) {
    Write-Host "Erreur: Vous devez fournir soit un token d'API, soit un nom d'utilisateur et un mot de passe." -ForegroundColor Red
    exit 1
}

# Créer le répertoire de sortie s'il n'existe pas
if (-not (Test-Path -Path $OutputPath)) {
    Write-VerboseMessage "Création du répertoire de sortie: $OutputPath"
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Construire l'URL complète
$fullUrl = "$ArtifactoryUrl/$Repository/$PackagePath"
Write-VerboseMessage "URL de téléchargement: $fullUrl"

# Préparer les en-têtes pour l'authentification
$headers = @{}

if (-not [string]::IsNullOrEmpty($ApiToken)) {
    Write-VerboseMessage "Utilisation de l'authentification par token API"
    $headers.Add("X-JFrog-Art-Api", $ApiToken)
} else {
    Write-VerboseMessage "Utilisation de l'authentification par nom d'utilisateur/mot de passe"
    $credPair = "$($Username):$($Password)"
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
        
        # Retourner le chemin du fichier pour une utilisation ultérieure
        return $outputFilePath
    } else {
        Write-Host "Erreur: Le fichier n'a pas été téléchargé." -ForegroundColor Red
        exit 1
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
    
    exit 1
}
