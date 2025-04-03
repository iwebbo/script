# Script PowerShell pour lister des packages depuis Artifactory via l'API search/artifact
# Recherche d'abord par nom d'application, puis raffine par dépôt spécifique si demandé

param (
    [Parameter(Mandatory=$true)]
    [string]$ArtifactoryUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$RepoNameSearch = "",
    
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

# Fonction pour rechercher les packages par nom d'application
function Search-ArtifactoryPackagesByName {
    param (
        [string]$AppName,
        [string]$RepoFilter = ""
    )
    
    # Construire l'URL de base
    $url = "$ArtifactoryUrl/api/search/artifact?name=$AppName"
    
    # Ajouter le filtre de dépôt si spécifié
    if (-not [string]::IsNullOrEmpty($RepoFilter)) {
        $url += "&repos=$RepoFilter"
    }
    
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
    Write-Host "Recherche des packages avec le nom '$Name'..."
    if (-not [string]::IsNullOrEmpty($RepoNameSearch)) {
        Write-Host "Filtré sur le dépôt: '$RepoNameSearch'" -ForegroundColor Yellow
    }
    
    # Tester la connexion avant de commencer
    if (-not (Test-ArtifactoryConnection)) {
        return
    }
    
    # Rechercher les packages
    $packages = Search-ArtifactoryPackagesByName -AppName $Name -RepoFilter $RepoNameSearch
    
    # Vérifier les résultats
    if ($null -eq $packages) {
        Write-Warning "La recherche a échoué. Vérifiez les paramètres et les logs pour plus de détails."
        return
    }
    
    if ($packages.Count -eq 0) {
        Write-Warning "Aucun package trouvé avec le nom '$Name'" + $(if (-not [string]::IsNullOrEmpty($RepoNameSearch)) { " dans le dépôt '$RepoNameSearch'" } else { "" })
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
    
    # Afficher un résumé des dépôts trouvés
    $repoSummary = $results | Group-Object -Property Repository | Select-Object Name, Count | Sort-Object -Property Count -Descending
    Write-Host "Packages trouvés par dépôt:" -ForegroundColor Cyan
    $repoSummary | Format-Table -AutoSize
    
    # Afficher les résultats
    $results | Format-Table -Property Repository, Name, Path, Type, Size, LastModified -AutoSize
    
    # Exporter vers un fichier CSV si demandé
    if ($OutputFile) {
        $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host "Résultats exportés vers $OutputFile" -ForegroundColor Green
    }
    
    return $results
}

# Exécution de la fonction principale
List-ArtifactoryPackages