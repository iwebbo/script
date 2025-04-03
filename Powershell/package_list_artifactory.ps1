# Script PowerShell pour lister des packages depuis Artifactory via l'API storage
# Ce script utilise "$ArtifactoryUrl/api/storage/$RepositoryName/" comme point d'entrée principal

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
    [string]$OutputFile
)

# Vérification des paramètres d'authentification
if (-not $ApiToken -and (-not $Username -or -not $Password)) {
    Write-Error "Vous devez fournir soit un ApiToken, soit un couple Username/Password."
    exit 1
}

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

# Fonction pour lister le contenu d'un chemin via l'API storage
function Get-ArtifactoryStorageContent {
    param (
        [string]$Path = ""
    )
    
    $url = "$ArtifactoryUrl/api/storage/$RepositoryName/$Path"
    $url = $url -replace "//+", "/"  # Éviter les doubles slashes
    $url = $url -replace ":/", "://"  # Corriger le protocole si nécessaire
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        return $response
    } catch {
        Write-Error "Erreur lors de l'accès à $url : $_"
        return $null
    }
}

# Fonction récursive pour parcourir les répertoires
function Get-ArtifactoryItemsRecursive {
    param (
        [string]$Path = "",
        [System.Collections.ArrayList]$Results
    )
    
    $response = Get-ArtifactoryStorageContent -Path $Path
    
    if ($null -eq $response) {
        return
    }
    
    # Si le chemin pointe vers un fichier, ajouter directement ses informations
    if ($response.PSObject.Properties.Name -contains "downloadUri") {
        $item = [PSCustomObject]@{
            Path = $Path
            Type = "File"
            Uri = $response.uri
            Size = $response.size
            Created = $response.created
            LastModified = $response.lastModified
            MimeType = $response.mimeType
            Checksums = if ($response.checksums) { 
                "SHA1: $($response.checksums.sha1), MD5: $($response.checksums.md5)"
            } else {
                ""
            }
        }
        
        # Filtrer par type si spécifié
        if ($PackageType -eq "*" -or $Path -match "\.$PackageType$") {
            [void]$Results.Add($item)
        }
        
        return
    }
    
    # Si c'est un répertoire, parcourir ses enfants
    if ($response.PSObject.Properties.Name -contains "children") {
        foreach ($child in $response.children) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) { 
                $child.uri -replace "^/" 
            } else { 
                "$Path/$($child.uri)" -replace "^/" 
            }
            
            $childPath = $childPath -replace "/+", "/"  # Normaliser les slashes
            
            if ($child.folder) {
                Write-Verbose "Exploration du répertoire: $childPath"
                
                if ($Recursive) {
                    Get-ArtifactoryItemsRecursive -Path $childPath -Results $Results
                }
            } else {
                # Obtenir les informations détaillées du fichier
                $fileInfo = Get-ArtifactoryStorageContent -Path $childPath
                
                if ($fileInfo) {
                    $item = [PSCustomObject]@{
                        Path = $childPath
                        Type = "File"
                        Uri = $fileInfo.uri
                        Size = $fileInfo.size
                        Created = $fileInfo.created
                        LastModified = $fileInfo.lastModified
                        MimeType = $fileInfo.mimeType
                        Checksums = if ($fileInfo.checksums) { 
                            "SHA1: $($fileInfo.checksums.sha1), MD5: $($fileInfo.checksums.md5)"
                        } else {
                            ""
                        }
                    }
                    
                    # Filtrer par type si spécifié
                    if ($PackageType -eq "*" -or $childPath -match "\.$PackageType$") {
                        [void]$Results.Add($item)
                    }
                }
            }
        }
    }
}

# Fonction principale
function List-ArtifactoryPackages {
    Write-Host "Listage des packages dans le dépôt $RepositoryName..."
    
    # Vérifier que le dépôt existe
    $repoCheck = Get-ArtifactoryStorageContent
    if ($null -eq $repoCheck) {
        Write-Error "Impossible d'accéder au dépôt $RepositoryName. Vérifiez que le dépôt existe et que vos identifiants sont corrects."
        return
    }
    
    # Créer une liste pour stocker les résultats
    $results = [System.Collections.ArrayList]::new()
    
    # Parcourir le dépôt de manière récursive si demandé
    Get-ArtifactoryItemsRecursive -Path "" -Results $results
    
    # Afficher les résultats
    if ($results.Count -eq 0) {
        Write-Warning "Aucun package trouvé dans le dépôt $RepositoryName avec le filtre '$PackageType'."
    } else {
        Write-Host "Nombre total de packages trouvés: $($results.Count)" -ForegroundColor Green
        
        # Formater et afficher les résultats
        $results | Format-Table -Property Path, Size, LastModified -AutoSize
        
        # Exporter vers un fichier CSV si demandé
        if ($OutputFile) {
            $results | Export-Csv -Path $OutputFile -NoTypeInformation
            Write-Host "Résultats exportés vers $OutputFile" -ForegroundColor Green
        }
    }
    
    return $results
}

# Exécution de la fonction principale
List-ArtifactoryPackages