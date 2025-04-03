# PowerShell script to interact with Artifactory
# Allows searching and deleting packages

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
    [switch]$UseCurlCommand
)

# Functions to format display messages
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

# Parameter validation
if ($DeleteMode -and [string]::IsNullOrEmpty($SpecificFile)) {
    Write-ErrorMessage "The -SpecificFile parameter is required in delete mode."
    exit 1
}

# Build URLs and curl commands based on parameters
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
    
    # Build curl command
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

# Function to convert storage URI to direct file URI
function Convert-ToDirectFileUri {
    param (
        [string]$Uri,
        [string]$Repo
    )
    
    # Replace /api/storage/ with / to get direct URL to file
    if ($Uri -match "/api/storage/") {
        $directUri = $Uri -replace "/api/storage/", "/"
        
        # Make sure the URL starts with the ArtifactoryUrl
        if (-not $directUri.StartsWith($ArtifactoryUrl)) {
            $directUri = "$ArtifactoryUrl/$Repo/" + ($directUri -replace "^.*?/$Repo/", "")
        }
        
        return $directUri
    }
    
    return $Uri
}

# Function to execute a search with Invoke-RestMethod
function Invoke-ArtifactorySearch {
    param (
        [hashtable]$CommandInfo
    )
    
    if ($UseCurlCommand) {
        Write-InfoMessage "Executing curl command:"
        Write-Host $CommandInfo.CurlCommand
        
        # Execute curl directly
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
            Write-ErrorMessage "Error during search: $_"
            return $null
        }
    }
}

# Function to execute a deletion
function Invoke-ArtifactoryDelete {
    param (
        [hashtable]$CommandInfo
    )
    
    if ($UseCurlCommand) {
        Write-InfoMessage "Executing curl command for deletion:"
        Write-Host $CommandInfo.CurlCommand
        
        # Execute curl directly
        $result = Invoke-Expression $CommandInfo.CurlCommand
        return $result
    } else {
        $headers = @{
            "Accept" = "application/json"
        }
        
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($CommandInfo.Auth))
        $headers["Authorization"] = "Basic $base64AuthInfo"
        
        if ($Verbose) {
            Write-InfoMessage "Deletion URL: $($CommandInfo.Url)"
        }
        
        try {
            $response = Invoke-RestMethod -Uri $CommandInfo.Url -Headers $headers -Method Delete
            return $response
        } catch {
            Write-ErrorMessage "Error during deletion: $_"
            return $null
        }
    }
}

# Main function
function Invoke-ArtifactoryOperation {
    if ($DeleteMode) {
        # Delete mode
        Write-WarningMessage "DELETE mode activated for file: $SpecificFile"
        Write-WarningMessage "Are you sure you want to delete this file? (Y/N)"
        $confirmation = Read-Host
        
        if ($confirmation -ne "Y" -and $confirmation -ne "y") {
            Write-InfoMessage "Operation cancelled."
            return
        }
        
        $commandInfo = Get-DeleteCommand
        $result = Invoke-ArtifactoryDelete -CommandInfo $commandInfo
        
        if ($result) {
            Write-SuccessMessage "File successfully deleted."
        }
    } else {
        # Search mode
        Write-InfoMessage "Searching in Artifactory"
        
        if (-not [string]::IsNullOrEmpty($PackageSearch)) {
            Write-InfoMessage "Package search: $PackageSearch"
        }
        
        if (-not [string]::IsNullOrEmpty($RepoNameSpecific)) {
            Write-InfoMessage "Specific repository: $RepoNameSpecific"
        }
        
        $commandInfo = Get-SearchCommand
        $result = Invoke-ArtifactorySearch -CommandInfo $commandInfo
        
        if ($null -eq $result) {
            Write-WarningMessage "No results found or error during search."
            return
        }
        
        # Process results
        if ($result.PSObject.Properties.Name -contains "results") {
            $items = $result.results
        } else {
            $items = $result
        }
        
        $count = $items.Count
        
        if ($count -eq 0) {
            Write-WarningMessage "No results found for this search."
            return
        }
        
        Write-SuccessMessage "Number of results found: $count"
        
        # Create PowerShell objects for results
        $formattedResults = @()
        
        foreach ($item in $items) {
            # Convert API URI to direct file URI
            $directUri = Convert-ToDirectFileUri -Uri $item.uri -Repo $item.repo
            
            $formattedItem = [PSCustomObject]@{
                Repository = $item.repo
                Path = $item.path
                Name = $item.name
                URI = $directUri
                Type = if ($item.name -match '\.([^\.]+)$') { $matches[1] } else { "Unknown" }
            }
            
            $formattedResults += $formattedItem
        }
        
        # Display summary by repository
        $repoSummary = $formattedResults | Group-Object -Property Repository | Select-Object Name, Count | Sort-Object -Property Count -Descending
        Write-InfoMessage "Results by repository:"
        $repoSummary | Format-Table -AutoSize
        
        # Display detailed results
        $formattedResults | Format-Table -AutoSize
        
        # Export to CSV if requested
        if ($OutputFile) {
            $formattedResults | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            Write-SuccessMessage "Results exported to $OutputFile"
        }
        
        return $formattedResults
    }
}

# Execute main function
Invoke-ArtifactoryOperation