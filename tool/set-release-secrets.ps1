# Uploads the release signing key from the gitignored keys/ folder to GitHub Actions secrets.
# Run from the repository root:  .\tool\set-release-secrets.ps1
# Requires: GitHub CLI (gh) logged in with access to the repository.
param([string]$Repo = "SanuSanal/gatekeeper")

$ErrorActionPreference = "Stop"
$props = Join-Path $PSScriptRoot "..\keys\key.properties"
$jks = Join-Path $PSScriptRoot "..\keys\gatekeeper-release.jks"
if (-not (Test-Path $props) -or -not (Test-Path $jks)) { throw "keys/key.properties or keys/gatekeeper-release.jks not found" }

$k = Get-Content $props -Raw | ConvertFrom-StringData
$keystore = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $jks)))

# --body avoids the trailing newline a pipe would add to the secret value.
gh secret set ANDROID_KEYSTORE_BASE64 --repo $Repo --body $keystore
gh secret set ANDROID_KEYSTORE_PASSWORD --repo $Repo --body $k.storePassword
gh secret set ANDROID_KEY_ALIAS --repo $Repo --body $k.keyAlias
gh secret set ANDROID_KEY_PASSWORD --repo $Repo --body $k.keyPassword

gh secret list --repo $Repo
