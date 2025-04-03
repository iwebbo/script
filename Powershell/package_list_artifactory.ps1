# Script PowerShell pour lister des packages depuis Artifactory
# Ce script supporte l'authentification par user/password ou par token API

param (
    [Parameter(Mandatory=$true)]
    [string]$ArtifactoryUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$RepositoryName,
    
    [Parameter(Mandatory=$false)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiToken,
    
    [Parameter(Mandatory=$false)]
    [string]$PackageType = "*",
    
    [Parameter(Mandatory=$false)]
    [int]$Limit = 100,
    
    [Parameter(Mandatory=$false)]
    [switch]$Recursive = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile
)

# Vérification des paramètres d'authentification
if (-not $ApiToken -and (-not $Username -or -not $Password)) {
    Write-Error "Vous devez fournir soit un ApiToken, soit un couple Username/Password."
    exit 1
}

# Construction de l'URL de base pour l'API Artifactory
$baseApiUrl = "$ArtifactoryUrl/api/storage/$RepositoryName"

# Configuration des headers pour l'authentification
$headers = @{
    "Accept" = "application/json"
}

if ($ApiToken) {
    $headers["X-JFrog-Art-Api"] = $ApiToken
} else {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
    $headers["Authorization"] = "Basic $base64AuthInfo"
}

# Fonction pour obtenir les éléments d'un répertoire
function Get-ArtifactoryItems {
    param (
        [string]$Path = ""
    )
    
    $url = if ([string]::IsNullOrEmpty($Path)) { $baseApiUrl } else { "$baseApiUrl/$Path" }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        return $response
    } catch {
        Write-Error "Erreur lors de la récupération des éléments: $_"
        return $null
    }
}

# Fonction récursive pour explorer les répertoires
function Get-ArtifactoryItemsRecursive {
    param (
        [string]$Path = "",
        [int]$CurrentDepth = 0
    )
    
    $response = Get-ArtifactoryItems -Path $Path
    
    if ($null -eq $response) {
        return
    }
    
    # Traitement du répertoire courant
    foreach ($child in $response.children) {
        $fullPath = if ([string]::IsNullOrEmpty($Path)) { $child.uri } else { "$Path$($child.uri)" }
        
        # Suppression du slash initial pour l'affichage
        $displayPath = $fullPath -replace "^/", ""
        
        if ($child.folder) {
            Write-Host "Répertoire: $displayPath"
            
            if ($Recursive) {
                # Appel récursif pour explorer les sous-répertoires
                Get-ArtifactoryItemsRecursive -Path $fullPath -CurrentDepth ($CurrentDepth + 1)
            }
        } else {
            # Récupération des informations détaillées sur le fichier
            $fileInfoUrl = "$ArtifactoryUrl/api/storage/$RepositoryName$fullPath"
            try {
                $fileInfo = Invoke-RestMethod -Uri $fileInfoUrl -Headers $headers -Method Get
                
                # Création d'un objet personnalisé pour l'affichage
                $packageInfo = [PSCustomObject]@{
                    Path = $displayPath
                    LastModified = $fileInfo.lastModified
                    Size = [math]::Round($fileInfo.size / 1KB, 2).ToString() + " KB"
                    SHA1 = $fileInfo.checksums.sha1
                    MimeType = $fileInfo.mimeType
                }
                
                # Filtrage par type si demandé
                if ($PackageType -eq "*" -or $displayPath -match $PackageType) {
                    $packageInfo
                }
            } catch {
                Write-Warning "Impossible d'obtenir les informations détaillées pour $displayPath : $_"
            }
        }
    }
}

# Fonction principale pour lister les packages
function List-ArtifactoryPackages {
    Write-Host "Listing des packages dans le dépôt $RepositoryName sur $ArtifactoryUrl..."
    Write-Host "Type de package: $PackageType"
    
    $packages = Get-ArtifactoryItemsRecursive
    
    if ($Limit -gt 0) {
        $packages = $packages | Select-Object -First $Limit
    }
    
    # Affichage des résultats à l'écran
    $packages | Format-Table -AutoSize
    
    # Exportation des résultats vers un fichier si demandé
    if ($OutputFile) {
        $packages | Export-Csv -Path $OutputFile -NoTypeInformation
        Write-Host "Résultats exportés vers $OutputFile"
    }
    
    Write-Host "Nombre total de packages trouvés: $($packages.Count)"
}

# Exécution de la fonction principale
List-ArtifactoryPackages
