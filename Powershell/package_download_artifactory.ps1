# Script to download a package from Artifactory
# Must be used in Entreprise, artifactory can be used with user/password or token

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
    
)

# Function verbose message 
function Write-VerboseMessage {
    param (
        [string]$Message
    )
    
    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose $Message
    }
}

# Check authentications 
if ([string]::IsNullOrEmpty($ApiToken) -and ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password))) {
    Write-Host "Error: Please fill a ApiToken or username & password." -ForegroundColor Red
    exit 1
}

# Create folder to download a package 
if (-not (Test-Path -Path $OutputPath)) {
    Write-VerboseMessage "Create folder of package: $OutputPath"
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Build link of Artifactory
$fullUrl = "$ArtifactoryUrl/$Repository/$PackagePath"
Write-VerboseMessage "Download from: $fullUrl"

# Head of authenfications 
$headers = @{}

if (-not [string]::IsNullOrEmpty($ApiToken)) {
    Write-VerboseMessage "Authentication from API"
    $headers.Add("X-JFrog-Art-Api", $ApiToken)
} else {
    Write-VerboseMessage "Authentication from username & password"
    $credPair = "$($Username):$($Password)"
    $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
    $headers.Add("Authorization", "Basic $encodedCredentials")
}

# Get file name
$fileName = Split-Path -Path $PackagePath -Leaf
$outputFilePath = Join-Path -Path $OutputPath -ChildPath $fileName

try {
    Write-Host "Download the package from artifactory..." -ForegroundColor Green
    

    $progressPreference = 'SilentlyContinue'  # Deactivate loading performance if package will be huge
    Invoke-WebRequest -Uri $fullUrl -Headers $headers -OutFile $outputFilePath -UseBasicParsing
    $progressPreference = 'Continue'  # Reactivate loading
    
    # Check if download has been succefully
    if (Test-Path -Path $outputFilePath) {
        $fileSize = (Get-Item -Path $outputFilePath).Length
        $fileSizeFormatted = "{0:N2} MB" -f ($fileSize / 1MB)
        Write-Host "Téléchargement réussi: $outputFilePath ($fileSizeFormatted)" -ForegroundColor Green
        
        # File path of package downloaded on local
        return $outputFilePath
    } else {
        Write-Host "Error: Package wasn't downloaded." -ForegroundColor Red
        exit 1
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    
    if ($statusCode -eq 401 -or $statusCode -eq 403) {
        Write-Host "Error of Authenfication (code $statusCode): Please check your token." -ForegroundColor Red
    } elseif ($statusCode -eq 404) {
        Write-Host "Error 404: Package not found, please check the link or package name" -ForegroundColor Red
    } else {
        Write-Host "Error with downloaded package, please check the permissions: $_" -ForegroundColor Red
    }
    
    exit 1
}
