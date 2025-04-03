# Script PowerShell pour lister des packages depuis Artifactory via l'API search
# Utilise l'API de recherche pour une meilleure performance

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
    [string]$PackageType = "",
    
    [Parameter(Mandatory=$false)]
    [int]$Limit = 1000,
    
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
    "Content-Type" = "text/plain"
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

# Fonction pour rechercher des packages avec AQL (Artifactory Query Language)
function Search-ArtifactoryPackagesWithAQL {
    param (
        [string]$RepoName,
        [string]$PackageType,
        [int]$LimitCount
    )
    
    # Préparation de la requête AQL
    $aqlQuery = "items.find({"
    $aqlQuery += "`"repo`":`"$RepoName`""
    
    # Ajouter une condition sur le type de package si spécifié
    if (-not [string]::IsNullOrEmpty($PackageType)) {
        $aqlQuery += ", `"name`":{`"`$match`":`"*.$PackageType`"}"
    }
    
    $aqlQuery += "}).sort({`"`$desc`":[`"name`"]}).limit($LimitCount)"
    
    if ($Verbose) {
        Write-Host "Requête AQL: $aqlQuery" -ForegroundColor Cyan
    }
    
    # Exécuter la requête AQL
    try {
        $url = "$ArtifactoryUrl/api/search/aql"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $aqlQuery -TimeoutSec $webTimeout
        return $response.results
    } catch {
        Write-Error "Erreur lors de la recherche AQL: $_"
        Write-Host "Réponse d'erreur: $($_.Exception.Response)"
        return $null
    }
}

# Fonction pour une recherche simple via l'API de recherche
function Search-ArtifactoryPackages {
    param (
        [string]$RepoName,
        [string]$PackageType,
        [int]$LimitCount
    )
    
    $urlParams = @{}
    $urlParams["repos"] = $RepoName
    
    if (-not [string]::IsNullOrEmpty($PackageType)) {
        $urlParams["name"] = "*.$PackageType"
    }
    
    # Construire l'URL avec les paramètres
    $url = "$ArtifactoryUrl/api/search/artifact"
    
    if ($Verbose) {
        Write-Host "URL de recherche: $url" -ForegroundColor Cyan
        Write-Host "Paramètres: $($urlParams | ConvertTo-Json -Compress)" -ForegroundColor Cyan
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -Body $urlParams -TimeoutSec $webTimeout
        
        if ($LimitCount -gt 0 -and $response.results.Count -gt $LimitCount) {
            return $response.results | Select-Object -First $LimitCount
        }
        
        return $response.results
    } catch {
        Write-Error "Erreur lors de la recherche: $_"
        return $null
    }
}

# Fonction pour obtenir des informations détaillées sur un package via l'API storage
function Get-PackageDetails {
    param (
        [string]$Uri
    )
    
    try {
        # Extraire le chemin relatif du URI
        $relativePath = $Uri -replace "^.*/api/storage/$RepositoryName/", ""
        $url = "$ArtifactoryUrl/api/storage/$RepositoryName/$relativePath"
        
        if ($Verbose) {
            Write-Host "Récupération des détails pour: $url" -ForegroundColor DarkCyan
        }
        
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec $webTimeout
        return $response
    } catch {
        Write-Warning "Impossible d'obtenir les détails pour $Uri : $_"
        return $null
    }
}

# Fonction principale
function List-ArtifactoryPackages {
    Write-Host "Recherche des packages dans le dépôt $RepositoryName..."
    
    # Tester la connexion avant de commencer
    if (-not (Test-ArtifactoryConnection)) {
        return
    }
    
    # Rechercher les packages avec AQL (plus puissant)
    Write-Host "Exécution de la recherche (limite: $Limit packages)..." -ForegroundColor Yellow
    $packages = Search-ArtifactoryPackagesWithAQL -RepoName $RepositoryName -PackageType $PackageType -LimitCount $Limit
    
    # Si AQL échoue, essayer avec l'API de recherche standard
    if ($null -eq $packages) {
        Write-Host "La recherche AQL a échoué, tentative avec l'API standard..." -ForegroundColor Yellow
        $packages = Search-ArtifactoryPackages -RepoName $RepositoryName -PackageType $PackageType -LimitCount $Limit
    }
    
    # Vérifier les résultats
    if ($null -eq $packages -or $packages.Count -eq 0) {
        Write-Warning "Aucun package trouvé dans le dépôt $RepositoryName" + 
                     $(if (-not [string]::IsNullOrEmpty($PackageType)) { " avec le type '$PackageType'" } else { "" })
        return
    }
    
    Write-Host "Nombre de packages trouvés: $($packages.Count)" -ForegroundColor Green
    
    # Transformer les résultats en objets pour l'affichage
    $results = @()
    $counter = 0
    
    foreach ($package in $packages) {
        $counter++
        Write-Progress -Activity "Traitement des packages" -Status "Package $counter sur $($packages.Count)" -PercentComplete (($counter * 100) / $packages.Count)
        
        # Extraire les informations de base
        $item = [PSCustomObject]@{
            Repository = $package.repo
            Path = $package.path
            Name = $package.name
            Type = if ($package.name -match '\.([^\.]+)$') { $matches[1] } else { "Unknown" }
            Size = if ($package.size) { [math]::Round($package.size / 1KB, 2).ToString() + " KB" } else { "N/A" }
            Created = $package.created
            Modified = $package.modified
            SHA1 = $package.actual_sha1
        }
        
        $results += $item
    }
    
    Write-Progress -Activity "Traitement des packages" -Completed
    
    # Afficher les résultats
    $results | Format-Table -Property Repository, Path, Name, Type, Size, Modified -AutoSize
    
    # Exporter vers un fichier CSV si demandé
    if ($OutputFile) {
        $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host "Résultats exportés vers $OutputFile" -ForegroundColor Green
    }
    
    return $results
}

# Exécution de la fonction principale
List-ArtifactoryPackages