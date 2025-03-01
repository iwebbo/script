# Set the username to the name of the user the certificate will be mapped to
$username = 'localuser'

$clientParams = @{
    CertStoreLocation = 'Cert:\CurrentUser\My'
    NotAfter          = (Get-Date).AddYears(1)
    Provider          = 'Microsoft Software Key Storage Provider'
    Subject           = "CN=$username"
    TextExtension     = @("2.5.29.37={text}1.3.6.1.5.5.7.3.2","2.5.29.17={text}upn=$username@localhost")
    Type              = 'Custom'
}
$cert = New-SelfSignedCertificate @clientParams
$certKeyName = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(
    $cert).Key.UniqueName

# Exports the public cert.pem and key cert.pfx
Set-Content -Path "cert.pem" -Value @(
    "-----BEGIN CERTIFICATE-----"
    [Convert]::ToBase64String($cert.RawData) -replace ".{64}", "$&`n"
    "-----END CERTIFICATE-----"
)
$certPfxBytes = $cert.Export('Pfx', '')
[System.IO.File]::WriteAllBytes("$pwd\cert.pfx", $certPfxBytes)

# Removes the private key and cert from the store after exporting
$keyPath = [System.IO.Path]::Combine($env:AppData, 'Microsoft', 'Crypto', 'Keys', $certKeyName)
Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
Remove-Item -LiteralPath $keyPath -Force