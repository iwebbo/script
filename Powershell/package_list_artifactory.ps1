# Script PowerShell pour lister des packages depuis Artifactory via l'API storage
# Avec gestion des timeouts et limites pour éviter les boucles infinies

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
    [switch]$Recursive = $false,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxDepth = 3,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxItems = 1000,
    
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

# Configuration du timeout pour les requêtes web (30 secondes)
$webTimeout = 30

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

# Définir un compteur global pour éviter les boucles infinies
$global:itemCount = 0
$global:processedPaths = @{}

# Fonction pour lister le contenu d'un chemin via l'API storage
function Get-ArtifactoryStorageContent {
    param (
        [string]$Path = ""
    )
    
    # Nettoyer le chemin
    $Path = $Path.TrimStart("/")
    
    # Construire l'URL
    $url = if ([string]::IsNullOrEmpty($Path)) {
        "$ArtifactoryUrl/api/storage/$RepositoryName"
    } else {
        "$ArtifactoryUrl/api/storage/$RepositoryName/$Path"
    }
    
    # Normaliser l'URL
    $url = $url -replace "([^:])//+", '$1/'
    
    if ($Verbose) {
        Write-Host "Accès à $url" -ForegroundColor Cyan
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec $webTimeout
        return $response
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Warning "Chemin non trouvé: $Path"
        } else {
            Write-Error "Erreur lors de l'accès à $url : $($_.Exception.Message)"
        }
        return $null
    }
}

# Fonction récursive limitée pour parcourir les répertoires
function Get-ArtifactoryItemsRecursive {
    param (
        [string]$Path = "",
        [System.Collections.ArrayList]$Results,
        [int]$CurrentDepth = 0
    )
    
    # Vérifier si on a atteint le nombre maximal d'items
    if ($global:itemCount -ge $MaxItems) {
        Write-Warning "Nombre maximal d'items atteint ($MaxItems). Arrêt du traitement."
        return
    }
    
    # Vérifier la profondeur maximale
    if ($CurrentDepth -gt $MaxDepth) {
        if ($Verbose) {
            Write-Host "Profondeur maximale atteinte pour $Path. Arrêt de la récursion." -ForegroundColor Yellow
        }
        return
    }
    
    # Vérifier si le chemin a déjà été traité (pour éviter les boucles)
    $pathKey = $Path.ToLower()
    if ($global:processedPaths.ContainsKey($pathKey)) {
        if ($Verbose) {
            Write-Host "Chemin déjà traité: $Path. Évitement de boucle." -ForegroundColor Yellow
        }
        return
    }
    
    # Marquer le chemin comme traité
    $global:processedPaths[$pathKey] = $true
    
    # Obtenir les informations du chemin actuel
    $response = Get-ArtifactoryStorageContent -Path $Path
    
    if ($null -eq $response) {
        return
    }
    
    # Si le chemin pointe vers un fichier, ajouter directement ses informations
    if ($response.PSObject.Properties.Name -contains "downloadUri") {
        $global:itemCount++
        
        $item = [PSCustomObject]@{
            Path = $Path
            Type = "File"
            Size = if ($response.size) { [math]::Round($response.size / 1KB, 2).ToString() + " KB" } else { "N/A" }
            LastModified = $response.lastModified
        }
        
        # Filtrer par type si spécifié
        if ($PackageType -eq "*" -or $Path -match "\.$PackageType$") {
            [void]$Results.Add($item)
            
            if ($Verbose) {
                Write-Host "Fichier ajouté: $Path" -ForegroundColor Green
            }
        }
        
        return
    }
    
    # Si c'est un répertoire, parcourir ses enfants
    if ($response.PSObject.Properties.Name -contains "children") {
        # Pour un suivi visuel de la progression
        Write-Progress -Activity "Exploration d'Artifactory" -Status "Dossier: $Path" -PercentComplete (($global:itemCount * 100) / [Math]::Max(1, $MaxItems))
        
        if ($Verbose) {
            Write-Host "Exploration du répertoire: $Path (profondeur $CurrentDepth)" -ForegroundColor Cyan
        }
        
        foreach ($child in $response.children) {
            # Vérifier à nouveau le compteur d'items
            if ($global:itemCount -ge $MaxItems) {
                Write-Warning "Nombre maximal d'items atteint ($MaxItems). Arrêt du traitement."
                return
            }
            
            $childUri = $child.uri -replace "^/"
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $childUri } else { "$Path/$childUri" }
            $childPath = $childPath -replace "/+", "/"
            
            if ($child.folder) {
                if ($Recursive) {
                    Get-ArtifactoryItemsRecursive -Path $childPath -Results $Results -CurrentDepth ($CurrentDepth + 1)
                }
            } else {
                $global:itemCount++
                
                $item = [PSCustomObject]@{
                    Path = $childPath
                    Type = "File"
                    Size = "À déterminer"
                    LastModified = "À déterminer"
                }
                
                # Filtrer par type si spécifié
                if ($PackageType -eq "*" -or $childPath -match "\.$PackageType$") {
                    # Obtenir les détails seulement si nécessaire
                    $fileInfo = Get-ArtifactoryStorageContent -Path $childPath
                    
                    if ($fileInfo) {
                        $item.Size = if ($fileInfo.size) { [math]::Round($fileInfo.size / 1KB, 2).ToString() + " KB" } else { "N/A" }
                        $item.LastModified = $fileInfo.lastModified
                    }
                    
                    [void]$Results.Add($item)
                    
                    if ($Verbose) {
                        Write-Host "Fichier ajouté: $childPath" -ForegroundColor Green
                    }
                }
            }
        }
    }
}

# Fonction principale
function List-ArtifactoryPackages {
    Write-Host "Listage des packages dans le dépôt $RepositoryName (type: $PackageType)..."
    
    # Tester la connexion avant de commencer
    if (-not (Test-ArtifactoryConnection)) {
        return
    }
    
    # Vérifier que le dépôt existe
    $repoCheck = Get-ArtifactoryStorageContent
    if ($null -eq $repoCheck) {
        Write-Error "Impossible d'accéder au dépôt $RepositoryName. Vérifiez que le dépôt existe et que vos identifiants sont corrects."
        return
    }
    
    # Informations sur les limites appliquées
    Write-Host "Limites: Maximum $MaxItems items, profondeur maximale de $MaxDepth" -ForegroundColor Yellow
    if ($Recursive) {
        Write-Host "Mode récursif activé" -ForegroundColor Yellow
    }
    
    # Réinitialiser les compteurs globaux
    $global:itemCount = 0
    $global:processedPaths = @{}
    
    # Créer une liste pour stocker les résultats
    $results = [System.Collections.ArrayList]::new()
    
    # Parcourir le dépôt
    Get-ArtifactoryItemsRecursive -Path "" -Results $results
    
    # Arrêter l'indicateur de progression
    Write-Progress -Activity "Exploration d'Artifactory" -Completed
    
    # Afficher les résultats
    if ($results.Count -eq 0) {
        Write-Warning "Aucun package trouvé dans le dépôt $RepositoryName avec le filtre '$PackageType'."
    } else {
        Write-Host "Nombre de packages trouvés: $($results.Count) sur $($global:itemCount) éléments analysés." -ForegroundColor Green
        
        # Formater et afficher les résultats
        $results | Format-Table -Property Path, Size, LastModified -AutoSize
        
        # Exporter vers un fichier CSV si demandé
        if ($OutputFile) {
            $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            Write-Host "Résultats exportés vers $OutputFile" -ForegroundColor Green
        }
    }
    
    return $results
}

# Exécution de la fonction principale
List-ArtifactoryPackages