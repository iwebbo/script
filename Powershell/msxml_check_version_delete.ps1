#Requires -RunAsAdministrator
<#
.SYNOPSIS
    This script checks for a specific MSXML version and removes it if found.

.DESCRIPTION
    The script checks if a specified MSXML version (e.g., 3.0, 4.0, 6.0) is installed
    by examining the registry and the corresponding DLL file. If found, it unregisters 
    and renames the DLL file to safely remove it from the system.

.PARAMETER Version
    Specifies the MSXML version to check and remove (e.g., "3.0", "3", "6.0", "6").

.PARAMETER Force
    If specified, the script will remove the specified version without asking for confirmation.

.EXAMPLE
    .\Remove-MSXML.ps1 -Version "3.0"
    Checks if MSXML 3.0 is installed and removes it after confirmation.

.EXAMPLE
    .\Remove-MSXML.ps1 -Version "6" -Force
    Checks if MSXML 6.0 is installed and removes it without confirmation.

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

# Function to create a drive to HKEY_CLASSES_ROOT if it doesn't exist
function Ensure-HKCRDrive {
    if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
        try {
            New-PSDrive -PSProvider Registry -Root HKEY_CLASSES_ROOT -Name HKCR -ErrorAction Stop | Out-Null
            Write-Host "Successfully created HKCR PSDrive." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create HKCR PSDrive: $($_.Exception.Message)" -ForegroundColor Red
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
    $msxmlInfo = $null
    
    # Check registry for version entries
    if (Test-Path $msxmlClsidPath) {
        Write-Host "Found MSXML registry entries." -ForegroundColor Green
        
        # Get all subkeys to see all versions
        $allVersions = Get-Item $msxmlClsidPath | Get-ChildItem
        Write-Host "All available MSXML versions in registry:" -ForegroundColor Green
        $allVersions | ForEach-Object { Write-Host "  - $($_.PSChildName)" -ForegroundColor Green }
        
        # Look for the specific version
        $versionEntries = $allVersions | Where-Object { $_.PSChildName -like "$Version*" }
        
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
                    Write-Host "  - Company: $($fileInfo.VersionInfo.CompanyName)" -ForegroundColor Green
                    
                    # Store info for removal
                    $msxmlInfo = @{
                        Version = $versionNumber
                        DLLPath = $dllPath
                        RegistryPath = $entry.PSPath
                        FileInfo = $fileInfo
                    }
                }
                else {
                    Write-Host "Warning: DLL file not found at path: $dllPath" -ForegroundColor Yellow
                    
                    # Still store the info even if DLL is missing
                    $msxmlInfo = @{
                        Version = $versionNumber
                        DLLPath = $dllPath
                        RegistryPath = $entry.PSPath
                        FileInfo = $null
                    }
                }
            }
        }
        else {
            Write-Host "MSXML version $Version not found in registry." -ForegroundColor Yellow
            
            # Check standard locations instead
            $possiblePaths = @(
                "$env:SystemRoot\System32\msxml$CleanVersion.dll",
                "$env:SystemRoot\SysWOW64\msxml$CleanVersion.dll"
            )
            
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    Write-Host "Found MSXML DLL at: $path" -ForegroundColor Green
                    $fileInfo = Get-Item $path
                    
                    # Store info for potential removal
                    $msxmlInfo = @{
                        Version = $Version
                        DLLPath = $path
                        RegistryPath = $null
                        FileInfo = $fileInfo
                    }
                    break
                }
            }
            
            # Also check for related DLLs like msxml4r.dll
            $relatedDllPath = "$env:SystemRoot\System32\msxml${CleanVersion}r.dll"
            $relatedDllPath64 = "$env:SystemRoot\SysWOW64\msxml${CleanVersion}r.dll"
            
            if (Test-Path $relatedDllPath) {
                Write-Host "Found related MSXML DLL at: $relatedDllPath" -ForegroundColor Green
                if ($msxmlInfo) {
                    $msxmlInfo.RelatedDLLPath = $relatedDllPath
                }
            }
            
            if (Test-Path $relatedDllPath64) {
                Write-Host "Found related MSXML DLL at: $relatedDllPath64" -ForegroundColor Green
                if ($msxmlInfo) {
                    $msxmlInfo.RelatedDLLPath64 = $relatedDllPath64
                }
            }
        }
    }
    else {
        Write-Host "MSXML registry path not found." -ForegroundColor Yellow
        
        # Still check standard locations
        $possiblePaths = @(
            "$env:SystemRoot\System32\msxml$CleanVersion.dll",
            "$env:SystemRoot\SysWOW64\msxml$CleanVersion.dll"
        )
        
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                Write-Host "Found MSXML DLL at: $path" -ForegroundColor Green
                $fileInfo = Get-Item $path
                
                # Store info for potential removal
                $msxmlInfo = @{
                    Version = $Version
                    DLLPath = $path
                    RegistryPath = $null
                    FileInfo = $fileInfo
                }
                break
            }
        }
        
        # Also check for related DLLs like msxml4r.dll
        $relatedDllPath = "$env:SystemRoot\System32\msxml${CleanVersion}r.dll"
        $relatedDllPath64 = "$env:SystemRoot\SysWOW64\msxml${CleanVersion}r.dll"
        
        if (Test-Path $relatedDllPath) {
            Write-Host "Found related MSXML DLL at: $relatedDllPath" -ForegroundColor Green
            if ($msxmlInfo) {
                $msxmlInfo.RelatedDLLPath = $relatedDllPath
            }
        }
        
        if (Test-Path $relatedDllPath64) {
            Write-Host "Found related MSXML DLL at: $relatedDllPath64" -ForegroundColor Green
            if ($msxmlInfo) {
                $msxmlInfo.RelatedDLLPath64 = $relatedDllPath64
            }
        }
    }
    
    return $msxmlInfo
}

# Function to remove the MSXML version using a direct approach
function Remove-MSXMLVersion {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$MSXMLInfo
    )
    
    Write-Host "Preparing to remove MSXML version $($MSXMLInfo.Version)..." -ForegroundColor Yellow
    
    $success = $true
    
    # Step 1: Handle the main DLL file
    if ($MSXMLInfo.DLLPath -and (Test-Path $MSXMLInfo.DLLPath)) {
        $dllFileName = Split-Path $MSXMLInfo.DLLPath -Leaf
        $dllDirectory = Split-Path $MSXMLInfo.DLLPath -Parent
        
        Write-Host "Processing $dllFileName in $dllDirectory..." -ForegroundColor Yellow
        
        try {
            # Change to the directory containing the DLL
            Push-Location $dllDirectory
            
            # Unregister the DLL
            Write-Host "Unregistering $dllFileName..." -ForegroundColor Yellow
            $process = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/u /s `"$dllFileName`"" -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Host "Successfully unregistered $dllFileName." -ForegroundColor Green
            }
            else {
                Write-Host "Warning: Failed to unregister $dllFileName. Exit code: $($process.ExitCode)" -ForegroundColor Yellow
                # Continue anyway as we'll rename the file
            }
            
            # Rename the DLL file (safer than deletion)
            Write-Host "Renaming $dllFileName to $dllFileName.save..." -ForegroundColor Yellow
            Rename-Item -Path $dllFileName -NewName "$dllFileName.save" -Force
            Write-Host "Successfully renamed $dllFileName to $dllFileName.save" -ForegroundColor Green
            
            # Return to previous directory
            Pop-Location
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Host "Error processing $dllFileName`: $errorMessage" -ForegroundColor Red
            $success = $false
            # Return to previous directory in case of error
            Pop-Location
        }
    }
    
    # Step 2: Handle related DLL files (like msxml4r.dll)
    if ($MSXMLInfo.RelatedDLLPath -and (Test-Path $MSXMLInfo.RelatedDLLPath)) {
        $relatedDllFileName = Split-Path $MSXMLInfo.RelatedDLLPath -Leaf
        $relatedDllDirectory = Split-Path $MSXMLInfo.RelatedDLLPath -Parent
        
        Write-Host "Processing related file $relatedDllFileName in $relatedDllDirectory..." -ForegroundColor Yellow
        
        try {
            # Change to the directory containing the DLL
            Push-Location $relatedDllDirectory
            
            # Unregister the DLL (if applicable)
            Write-Host "Unregistering $relatedDllFileName..." -ForegroundColor Yellow
            $process = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/u /s `"$relatedDllFileName`"" -Wait -PassThru -NoNewWindow
            
            # Rename the DLL file
            Write-Host "Renaming $relatedDllFileName to $relatedDllFileName.save..." -ForegroundColor Yellow
            Rename-Item -Path $relatedDllFileName -NewName "$relatedDllFileName.save" -Force
            Write-Host "Successfully renamed $relatedDllFileName to $relatedDllFileName.save" -ForegroundColor Green
            
            # Return to previous directory
            Pop-Location
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Host "Error processing $relatedDllFileName`: $errorMessage" -ForegroundColor Red
            # Return to previous directory in case of error
            Pop-Location
        }
    }
    
    # Step 3: Handle related DLL files in SysWOW64 (for 64-bit systems)
    if ($MSXMLInfo.RelatedDLLPath64 -and (Test-Path $MSXMLInfo.RelatedDLLPath64)) {
        $relatedDllFileName64 = Split-Path $MSXMLInfo.RelatedDLLPath64 -Leaf
        $relatedDllDirectory64 = Split-Path $MSXMLInfo.RelatedDLLPath64 -Parent
        
        Write-Host "Processing related file $relatedDllFileName64 in $relatedDllDirectory64..." -ForegroundColor Yellow
        
        try {
            # Change to the directory containing the DLL
            Push-Location $relatedDllDirectory64
            
            # Unregister the DLL (if applicable)
            Write-Host "Unregistering $relatedDllFileName64..." -ForegroundColor Yellow
            $process = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/u /s `"$relatedDllFileName64`"" -Wait -PassThru -NoNewWindow
            
            # Rename the DLL file
            Write-Host "Renaming $relatedDllFileName64 to $relatedDllFileName64.save..." -ForegroundColor Yellow
            Rename-Item -Path $relatedDllFileName64 -NewName "$relatedDllFileName64.save" -Force
            Write-Host "Successfully renamed $relatedDllFileName64 to $relatedDllFileName64.save" -ForegroundColor Green
            
            # Return to previous directory
            Pop-Location
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Host "Error processing $relatedDllFileName64`: $errorMessage" -ForegroundColor Red
            # Return to previous directory in case of error
            Pop-Location
        }
    }
    
    # Step 4: Remove registry entries if they exist
    if ($MSXMLInfo.RegistryPath) {
        try {
            Write-Host "Removing registry entries..." -ForegroundColor Yellow
            Remove-Item -Path $MSXMLInfo.RegistryPath -Force -Recurse
            Write-Host "Successfully removed registry entries." -ForegroundColor Green
        }
        catch {
            Write-Host "Error removing registry entries: $($_.Exception.Message)" -ForegroundColor Red
            $success = $false
        }
    }
    
    if ($success) {
        Write-Host "Successfully removed MSXML version $($MSXMLInfo.Version)." -ForegroundColor Green
    }
    else {
        Write-Host "Failed to completely remove MSXML version $($MSXMLInfo.Version)." -ForegroundColor Red
    }
    
    return $success
}

# Main script execution
# Check if the specified MSXML version is installed
$msxmlInfo = Check-MSXMLVersion -Version $Version

if ($msxmlInfo) {
    # Ask for confirmation unless -Force is specified
    $proceed = $Force
    
    if (-not $Force) {
        $confirmation = Read-Host "Do you want to remove MSXML version $($msxmlInfo.Version)? (Y/N)"
        $proceed = ($confirmation -eq 'Y' -or $confirmation -eq 'y')
    }
    
    if ($proceed) {
        $result = Remove-MSXMLVersion -MSXMLInfo $msxmlInfo
        
        if ($result) {
            Write-Host "MSXML version $($msxmlInfo.Version) has been successfully removed." -ForegroundColor Green
        }
        else {
            Write-Host "Failed to completely remove MSXML version $($msxmlInfo.Version)." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    }
}
else {
    Write-Host "MSXML version $Version is not installed on this system." -ForegroundColor Yellow
}

# Verify after removal
if ($msxmlInfo) {
    Write-Host "`nVerifying removal..." -ForegroundColor Cyan
    $checkAfter = Check-MSXMLVersion -Version $Version
    
    if (-not $checkAfter) {
        Write-Host "Verification confirmed: MSXML version $Version has been successfully removed." -ForegroundColor Green
    }
    else {
        Write-Host "Verification failed: MSXML version $Version is still present on the system." -ForegroundColor Red
    }
}
