# Vérifier si le script est exécuté en mode administrateur
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $IsAdmin) {
    Write-Host "Veuillez exécuter ce script en tant qu'Administrateur." -ForegroundColor Red
    exit 1
}

# Détecter le DisplayName du service WinRM en fonction de la langue du système
$winrmService = Get-Service | Where-Object { $_.Name -eq "WinRM" }
if (-not $winrmService) {
    Write-Host "Le service WinRM n'est pas installé sur ce système." -ForegroundColor Red
    exit 1
}

$winrmDisplayName = $winrmService.DisplayName
Write-Host "Service WinRM détecté : $winrmDisplayName"

# Vérifier si WinRM est actif et l'activer si nécessaire
if ($winrmService.Status -ne "Running") {
    Write-Host "Activation du service WinRM..."
    winrm quickconfig -force
}

# Appliquer la configuration nécessaire à WinRM
Write-Host "Configuration de WinRM..."
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\Auth\NTLM -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Ajouter une règle de pare-feu pour autoriser WinRM sur le port 5985
Write-Host "Ajout de la règle de pare-feu pour WinRM..."
netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall add rule name="WinRM HTTPS" dir=in action=allow protocol=TCP localport=5986

# Vérifier le profil réseau (public ou privé)
$networkProfile = Get-NetConnectionProfile
if ($networkProfile.NetworkCategory -eq "Public") {
    Write-Host "Le réseau est actuellement en mode Public. Modification en mode Privé..."
    
    try {
        Set-NetConnectionProfile -NetworkCategory Private
        Write-Host "Le réseau a été changé en mode Privé."
    } catch {
        Write-Host "Impossible de changer le réseau en mode Privé. Vérifiez les permissions." -ForegroundColor Red
        exit 1
    }

    # Relancer la configuration WinRM après modification du réseau
    Write-Host "Reconfiguration de WinRM après modification du réseau..."
    winrm quickconfig -force
}

Write-Host "Configuration WinRM terminée avec succès !" -ForegroundColor Green
