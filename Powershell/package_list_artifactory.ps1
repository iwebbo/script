# Script PowerShell pour lister des packages depuis Artifactory via l'API search/artifact
# Version simplifiée avec l'API directe api/search/artifact?name=name&repos=repo-name-search

param (
    [Parameter(Mandatory=$true)]
    [string]$ArtifactoryUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$RepoNameSearch,
    
    [Parameter(Mandatory=$false)]
    [string]$Name = "*",
    
    [Parameter(Mandatory=$false)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiToken,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Vérification des paramètres d'authentification
if (-not $ApiToken -and (-not $Username -or -not $Password)) {
    Write-Error "Vous devez fournir soit un ApiToken, soit un couple Username/Password."
    exit 1
}

# Configuration du timeout pour les requêtes web (60 secondes)
$webTimeout = 60

# Construction des headers pour l'authentification
$headers = @{
    "Accept" = "application/json"
}

if ($ApiToken) {
    $headers["X-JFrog-Art-Api"] = $ApiToken
} else {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
    $headers["Authorization"] = "Basic $base64AuthInfo"
}

# Fonction pour tester la connexion
function Test-ArtifactoryConnection {
    try {
        $url = "$ArtifactoryUrl/api/system/ping"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec $webTimeout
        Write-Host "Connexion à Artifactory réussie" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Échec de connexion à Artifactory: $_"
        return $false
    }
}

# Fonction principale pour rechercher les packages avec le format d'URL spécifié
function Search-ArtifactoryPackages {
    # Construire l'URL comme spécifié
    $url = "$ArtifactoryUrl/api/search/artifact?name=$Name&repos=$RepoNameSearch"
    
    if ($Verbose) {
        Write-Host "URL de recherche: $url" -ForegroundColor Cyan
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec $webTimeout
        return $response.results
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Error "Erreur lors de la recherche (Code: $statusCode): $_"
        
        if ($statusCode -eq 406) {
            Write-Host "Erreur 406 (Not Acceptable): Vérifiez que vos en-têtes Accept sont correctement configurés." -ForegroundColor Red
        }
        
        return $null
    }
}

# Fonction principale
function List-ArtifactoryPackages {
    Write-Host "Recherche des packages dans le dépôt '$RepoNameSearch' avec le motif de nom '$Name'..."
    
    # Tester la connexion avant de commencer
    if (-not (Test-ArtifactoryConnection)) {
        return
    }
    
    # Rechercher les packages
    $packages = Search-ArtifactoryPackages
    
    # Vérifier les résultats
    if ($null -eq $packages) {
        Write-Warning "La recherche a échoué. Vérifiez les paramètres et les logs pour plus de détails."
        return
    }
    
    if ($packages.Count -eq 0) {
        Write-Warning "Aucun package trouvé pour le dépôt '$RepoNameSearch' avec le motif de nom '$Name'."
        return
    }
    
    Write-Host "Nombre de packages trouvés: $($packages.Count)" -ForegroundColor Green
    
    # Transformer les résultats en objets pour l'affichage
    $results = @()
    
    foreach ($package in $packages) {
        # Extraire les informations de base
        $item = [PSCustomObject]@{
            URI = $package.uri
            Repository = $package.repo
            Path = $package.path
            Name = $package.name
            Type = if ($package.name -match '\.([^\.]+)$') { $matches[1] } else { "Unknown" }
            Size = if ($package.size) { [math]::Round($package.size / 1KB, 2).ToString() + " KB" } else { "N/A" }
            LastModified = $package.lastModified
        }
        
        $results += $item
    }
    
    # Afficher les résultats
    $results | Format-Table -Property Repository, Path, Name, Type, Size, LastModified -AutoSize
    
    # Exporter vers un fichier CSV si demandé
    if ($OutputFile) {
        $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host "Résultats exportés vers $OutputFile" -ForegroundColor Green
    }
    
    return $results
}

# Exécution de la fonction principale
List-ArtifactoryPackages