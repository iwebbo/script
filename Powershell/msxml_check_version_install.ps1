#Requires -RunAsAdministrator
<#
.SYNOPSIS
    This script installs a specific MSXML version from Microsoft's official sources.

.DESCRIPTION
    The script downloads and installs a specified MSXML version (e.g., 3.0, 4.0, 6.0) 
    from official Microsoft download links. It verifies if the version is already installed
    before proceeding with the download and installation.

.PARAMETER Version
    Specifies the MSXML version to install (e.g., "3.0", "3", "4.0", "4", "6.0", "6").

.PARAMETER Force
    If specified, the script will install even if a version is already detected.

.EXAMPLE
    .\Install-MSXML.ps1 -Version "3.0"
    Checks if MSXML 3.0 is installed, and if not, downloads and installs it.

.EXAMPLE
    .\Install-MSXML.ps1 -Version "4.0" -Force
    Downloads and installs MSXML 4.0 regardless of whether it's already installed.

.NOTES
    Author: Your Name
    Date: Current Date
    Requires: PowerShell 5.1 or higher, Administrator privileges
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Clean up version input (remove decimals if present)
$CleanVersion = $Version.Split('.')[0]

# Define download URLs for different MSXML versions
$msxmlDownloads = @{
    "3" = @{
        "x86" = "https://download.microsoft.com/download/8/8/8/888f34b7-4f54-4f06-8dac-fa29b19f33dd/msxml3.msi";
        "x64" = "https://download.microsoft.com/download/8/8/8/888f34b7-4f54-4f06-8dac-fa29b19f33dd/msxml3.msi"; # Same file for both architectures
        "Description" = "Microsoft XML Parser (MSXML) 3.0";
    };
    "4" = @{
        "x86" = "https://download.microsoft.com/download/A/2/D/A2D8587D-0027-4217-9DAD-38AFDB0A177E/msxml.msi";
        "x64" = "https://download.microsoft.com/download/A/2/D/A2D8587D-0027-4217-9DAD-38AFDB0A177E/msxml.msi"; # Same file for both architectures
        "Description" = "Microsoft XML Core Services (MSXML) 4.0 SP2";
    };
    "6" = @{
        "x86" = "https://download.microsoft.com/download/e/2/e/e2e92e52-210b-4774-8cd9-3a15db08b3ac/msxml6_x86.msi";
        "x64" = "https://download.microsoft.com/download/e/2/e/e2e92e52-210b-4774-8cd9-3a15db08b3ac/msxml6_x64.msi";
        "Description" = "Microsoft XML Core Services (MSXML) 6.0";
    };
}

# Function to create a drive to HKEY_CLASSES_ROOT if it doesn't exist
function Ensure-HKCRDrive {
    if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
        try {
            New-PSDrive -PSProvider Registry -Root HKEY_CLASSES_ROOT -Name HKCR -ErrorAction Stop | Out-Null
            Write-Host "Successfully created HKCR PSDrive." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create HKCR PSDrive: $_" -ForegroundColor Red
            exit 1
        }
    }
}

# Function to check if a specific MSXML version is installed
function Check-MSXMLVersion {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version
    )
    
    Ensure-HKCRDrive
    
    Write-Host "Checking if MSXML $Version is installed..." -ForegroundColor Cyan
    
    $msxmlClsidPath = "HKCR:\CLSID\{2933BF90-7B36-11D2-B20E-00C04F983E60}\VersionList"
    $isInstalled = $false
    $dllPath = $null
    
    # Check registry for version entries
    if (Test-Path $msxmlClsidPath) {
        Write-Host "Found MSXML registry entries." -ForegroundColor Green
        
        # Look for the specific version
        $versionEntries = Get-Item $msxmlClsidPath | Get-ChildItem | Where-Object { $_.PSChildName -like "$Version*" }
        
        if ($versionEntries) {
            foreach ($entry in $versionEntries) {
                $versionNumber = $entry.PSChildName
                $properties = $entry | Get-ItemProperty
                
                # Get DLL path
                $dllPath = $properties.'(default)' -replace '"', ''
                
                Write-Host "Found MSXML version $versionNumber" -ForegroundColor Green
                Write-Host "DLL Path: $dllPath" -ForegroundColor Green
                
                # Check if the DLL exists
                if (Test-Path $dllPath) {
                    Write-Host "DLL file exists at the specified path." -ForegroundColor Green
                    $fileInfo = Get-Item $dllPath
                    Write-Host "DLL Details:" -ForegroundColor Green
                    Write-Host "  - File Version: $($fileInfo.VersionInfo.FileVersion)" -ForegroundColor Green
                    Write-Host "  - Product Version: $($fileInfo.VersionInfo.ProductVersion)" -ForegroundColor Green
                    
                    $isInstalled = $true
                }
                else {
                    Write-Host "Warning: DLL file not found at path: $dllPath" -ForegroundColor Yellow
                }
            }
        }
        else {
            Write-Host "MSXML version $Version not found in registry." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "MSXML registry path not found." -ForegroundColor Yellow
    }
    
    # Check standard DLL location if not found in registry
    if (-not $isInstalled) {
        $standardDllPath = "$env:SystemRoot\System32\msxml$CleanVersion.dll"
        if (Test-Path $standardDllPath) {
            Write-Host "Found MSXML DLL at standard path: $standardDllPath" -ForegroundColor Green
            $fileInfo = Get-Item $standardDllPath
            Write-Host "DLL Details:" -ForegroundColor Green
            Write-Host "  - File Version: $($fileInfo.VersionInfo.FileVersion)" -ForegroundColor Green
            Write-Host "  - Product Version: $($fileInfo.VersionInfo.ProductVersion)" -ForegroundColor Green
            
            $isInstalled = $true
            $dllPath = $standardDllPath
        }
        else {
            Write-Host "No MSXML $Version DLL found at standard path." -ForegroundColor Yellow
        }
    }
    
    return @{
        IsInstalled = $isInstalled
        DLLPath = $dllPath
    }
}

# Function to download and install MSXML
function Install-MSXML {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version
    )
    
    # Check if download info exists for the requested version
    if (-not $msxmlDownloads.ContainsKey($CleanVersion)) {
        Write-Host "Error: No download information available for MSXML version $Version." -ForegroundColor Red
        Write-Host "Supported versions: 3.0, 4.0, 6.0" -ForegroundColor Yellow
        return $false
    }
    
    $versionInfo = $msxmlDownloads[$CleanVersion]
    
    # Determine system architecture
    $architecture = "x86"
    if ([Environment]::Is64BitOperatingSystem) {
        $architecture = "x64"
    }
    
    $downloadUrl = $versionInfo[$architecture]
    $description = $versionInfo["Description"]
    
    Write-Host "Preparing to download $description for $architecture..." -ForegroundColor Cyan
    
    # Create temporary directory
    $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "MSXML_Install_$CleanVersion")
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    # Download the installer
    $installerPath = [System.IO.Path]::Combine($tempDir, "msxml$CleanVersion.msi")
    Write-Host "Downloading from: $downloadUrl" -ForegroundColor Yellow
    Write-Host "Saving to: $installerPath" -ForegroundColor Yellow
    
    try {
        # Create a webclient for the download
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell Script")
        $webClient.DownloadFile($downloadUrl, $installerPath)
        
        Write-Host "Download completed successfully." -ForegroundColor Green
        
        # Install the MSI package
        Write-Host "Installing $description..." -ForegroundColor Yellow
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn" -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Successfully installed $description." -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error during download or installation: $_" -ForegroundColor Red
        return $false
    }
    finally {
        # Clean up temporary files
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force
        }
    }
}

# Main script execution
# Check if the specified MSXML version is already installed
$msxmlStatus = Check-MSXMLVersion -Version $Version

if ($msxmlStatus.IsInstalled -and -not $Force) {
    Write-Host "MSXML version $Version is already installed." -ForegroundColor Green
    Write-Host "Use -Force parameter to reinstall if needed." -ForegroundColor Yellow
}
else {
    if ($msxmlStatus.IsInstalled) {
        Write-Host "MSXML version $Version is already installed, but Force parameter was specified. Proceeding with reinstallation..." -ForegroundColor Yellow
    }
    else {
        Write-Host "MSXML version $Version is not installed. Proceeding with installation..." -ForegroundColor Yellow
    }
    
    $result = Install-MSXML -Version $Version
    
    if ($result) {
        Write-Host "MSXML version $Version has been successfully installed." -ForegroundColor Green
    }
    else {
        Write-Host "Failed to install MSXML version $Version." -ForegroundColor Red
    }
}

# Verify after installation
Write-Host "`nVerifying installation..." -ForegroundColor Cyan
$verifyStatus = Check-MSXMLVersion -Version $Version

if ($verifyStatus.IsInstalled) {
    Write-Host "Verification confirmed: MSXML version $Version is successfully installed." -ForegroundColor Green
}
else {
    Write-Host "Verification failed: MSXML version $Version does not appear to be properly installed." -ForegroundColor Red
}
