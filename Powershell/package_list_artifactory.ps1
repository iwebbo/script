# Script PowerShell pour interagir avec Artifactory
# Permet de rechercher et supprimer des packages

param (
    [Parameter(Mandatory=$true)]
    [string]$ArtifactoryUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$false)]
    [string]$PackageSearch = "",
    
    [Parameter(Mandatory=$false)]
    [string]$RepoNameSpecific = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SpecificFile = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$DeleteMode,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseCurlCommand,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Fonctions pour formater les affichages
function Write-InfoMessage {
    param (
        [string]$Message
    )
    Write-Host $Message -ForegroundColor Cyan
}

function Write-SuccessMessage {
    param (
        [string]$Message
    )
    Write-Host $Message -ForegroundColor Green
}

function Write-WarningMessage {
    param (
        [string]$Message
    )
    Write-Host $Message -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param (
        [string]$Message
    )
    Write-Host $Message -ForegroundColor Red
}

# Validation des paramètres
if ($DeleteMode -and [string]::IsNullOrEmpty($SpecificFile)) {
    Write-ErrorMessage "Le paramètre -SpecificFile est requis en mode suppression."
    exit 1
}

# Construction des URL et commandes curl en fonction des paramètres
function Get-SearchCommand {
    $baseUrl = "$ArtifactoryUrl/api/search/artifact"
    $authPart = "$Username`:$Token"
    
    if (-not [string]::IsNullOrEmpty($PackageSearch)) {
        $baseUrl += "?name=$PackageSearch"
        
        if (-not [string]::IsNullOrEmpty($RepoNameSpecific)) {
            $baseUrl += "&repos=$RepoNameSpecific"
        }
    } elseif (-not [string]::IsNullOrEmpty($RepoNameSpecific)) {
        $baseUrl += "?repos=$RepoNameSpecific"
    }
    
    # Construire la commande curl
    $curlCommand = "curl -ks `"https://$authPart@$($ArtifactoryUrl.Replace('https://', ''))/api/search/artifact"
    
    if (-not [string]::IsNullOrEmpty($PackageSearch)) {
        $curlCommand += "?name=$PackageSearch"
        
        if (-not [string]::IsNullOrEmpty($RepoNameSpecific)) {
            $curlCommand += "&repos=$RepoNameSpecific"
        }
    } elseif (-not [string]::IsNullOrEmpty($RepoNameSpecific)) {
        $curlCommand += "?repos=$RepoNameSpecific"
    }
    
    $curlCommand += "`""
    
    return @{
        Url = $baseUrl
        Auth = $authPart
        CurlCommand = $curlCommand
    }
}

function Get-DeleteCommand {
    $authPart = "$Username`:$Token"
    $curlCommand = "curl -ku $authPart -X DELETE `"$SpecificFile`""
    
    return @{
        Url = $SpecificFile
        Auth = $authPart
        CurlCommand = $curlCommand
    }
}

# Fonction pour exécuter une recherche avec Invoke-RestMethod
function Invoke-ArtifactorySearch {
    param (
        [hashtable]$CommandInfo
    )
    
    if ($UseCurlCommand) {
        Write-InfoMessage "Exécution de la commande curl:"
        Write-Host $CommandInfo.CurlCommand
        
        # Exécuter curl directement
        $result = Invoke-Expression $CommandInfo.CurlCommand
        return $result | ConvertFrom-Json
    } else {
        $headers = @{
            "Accept" = "application/json"
        }
        
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($CommandInfo.Auth))
        $headers["Authorization"] = "Basic $base64AuthInfo"
        
        if ($Verbose) {
            Write-InfoMessage "URL: $($CommandInfo.Url)"
            Write-InfoMessage "Headers: $(ConvertTo-Json $headers -Compress)"
        }
        
        try {
            $response = Invoke-RestMethod -Uri $CommandInfo.Url -Headers $headers -Method Get
            return $response
        } catch {
            Write-ErrorMessage "Erreur lors de la recherche: $_"
            return $null
        }
    }
}

# Fonction pour exécuter une suppression
function Invoke-ArtifactoryDelete {
    param (
        [hashtable]$CommandInfo
    )
    
    if ($UseCurlCommand) {
        Write-InfoMessage "Exécution de la commande curl pour suppression:"
        Write-Host $CommandInfo.CurlCommand
        
        # Exécuter curl directement
        $result = Invoke-Expression $CommandInfo.CurlCommand
        return $result
    } else {
        $headers = @{
            "Accept" = "application/json"
        }
        
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($CommandInfo.Auth))
        $headers["Authorization"] = "Basic $base64AuthInfo"
        
        if ($Verbose) {
            Write-InfoMessage "URL de suppression: $($CommandInfo.Url)"
        }
        
        try {
            $response = Invoke-RestMethod -Uri $CommandInfo.Url -Headers $headers -Method Delete
            return $response
        } catch {
            Write-ErrorMessage "Erreur lors de la suppression: $_"
            return $null
        }
    }
}

# Fonction principale
function Invoke-ArtifactoryOperation {
    if ($DeleteMode) {
        # Mode suppression
        Write-WarningMessage "Mode SUPPRESSION activé pour le fichier: $SpecificFile"
        Write-WarningMessage "Êtes-vous sûr de vouloir supprimer ce fichier? (O/N)"
        $confirmation = Read-Host
        
        if ($confirmation -ne "O" -and $confirmation -ne "o") {
            Write-InfoMessage "Opération annulée."
            return
        }
        
        $commandInfo = Get-DeleteCommand
        $result = Invoke-ArtifactoryDelete -CommandInfo $commandInfo
        
        if ($result) {
            Write-SuccessMessage "Fichier supprimé avec succès."
        }
    } else {
        # Mode recherche
        Write-InfoMessage "Recherche dans Artifactory"
        
        if (-not [string]::IsNullOrEmpty($PackageSearch)) {
            Write-InfoMessage "Package recherché: $PackageSearch"
        }
        
        if (-not [string]::IsNullOrEmpty($RepoNameSpecific)) {
            Write-InfoMessage "Dépôt spécifique: $RepoNameSpecific"
        }
        
        $commandInfo = Get-SearchCommand
        $result = Invoke-ArtifactorySearch -CommandInfo $commandInfo
        
        if ($null -eq $result) {
            Write-WarningMessage "Aucun résultat trouvé ou erreur lors de la recherche."
            return
        }
        
        # Traiter les résultats
        if ($result.PSObject.Properties.Name -contains "results") {
            $items = $result.results
        } else {
            $items = $result
        }
        
        $count = $items.Count
        
        if ($count -eq 0) {
            Write-WarningMessage "Aucun résultat trouvé pour cette recherche."
            return
        }
        
        Write-SuccessMessage "Nombre de résultats trouvés: $count"
        
        # Créer des objets PowerShell pour les résultats
        $formattedResults = @()
        
        foreach ($item in $items) {
            $formattedItem = [PSCustomObject]@{
                Repository = $item.repo
                Path = $item.path
                Name = $item.name
                URI = $item.uri
                Type = if ($item.name -match '\.([^\.]+)$') { $matches[1] } else { "Unknown" }
            }
            
            $formattedResults += $formattedItem
        }
        
        # Afficher un résumé par dépôt
        $repoSummary = $formattedResults | Group-Object -Property Repository | Select-Object Name, Count | Sort-Object -Property Count -Descending
        Write-InfoMessage "Résultats par dépôt:"
        $repoSummary | Format-Table -AutoSize
        
        # Afficher les résultats détaillés
        $formattedResults | Format-Table -AutoSize
        
        # Exporter vers un fichier CSV si demandé
        if ($OutputFile) {
            $formattedResults | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            Write-SuccessMessage "Résultats exportés vers $OutputFile"
        }
        
        return $formattedResults
    }
}

# Exécution de la fonction principale
Invoke-ArtifactoryOperation