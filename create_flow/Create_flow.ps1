<#
.SYNOPSIS
  Wraps the Consumption Central "Copilot Studio credits" flow file into a Power Automate
  legacy import package (.zip) you can import from any browser.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Build-StudioFlowPackage.ps1 `
    -FlowFile "$env:USERPROFILE\Documents\Consumption Central\consumption-central-studio-credits-flow.json"

  Writes ConsumptionCentral-StudioCredits.zip next to the flow file.
  Works in Windows PowerShell 5.1 and PowerShell 7. Reads only the flow file; sends nothing anywhere.
#>
param(
  [Parameter(Mandatory = $true)][string]$FlowFile,
  [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$FlowFile = (Resolve-Path $FlowFile).Path
if (-not $OutFile) { $OutFile = Join-Path (Split-Path $FlowFile) 'ConsumptionCentral-StudioCredits.zip' }

$raw = [System.IO.File]::ReadAllText($FlowFile, [System.Text.Encoding]::UTF8)
$file = $raw | ConvertFrom-Json
if (-not $file.definition) { throw "No 'definition' in $FlowFile - is this the installer's flow file?" }
$displayName = if ($file.name) { [string]$file.name } else { 'Consumption Central - Copilot Studio credits' }

# Take the definition's text exactly as the installer wrote it, so nothing is re-serialised.
$m = [regex]::Match($raw, '"definition"\s*:\s*\{')
if (-not $m.Success) { throw "Couldn't find the definition in $FlowFile." }
$start = $m.Index + $m.Length - 1
$end = $raw.LastIndexOf('}')            # the file's own closing brace
$defText = $raw.Substring($start, $end - $start).TrimEnd()
$null = $defText | ConvertFrom-Json      # sanity check: must parse on its own

# The connection references the flow uses (e.g. shared_webcontents, shared_webcontents_storage).
$refs = [regex]::Matches($defText, '"connectionName"\s*:\s*"([^"]+)"') |
  ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
if (-not $refs) { throw 'The definition uses no connections - unexpected.' }

function Api-Of([string]$ref) { if ($ref -like 'shared_webcontents*') { 'shared_webcontents' } else { $ref } }
function Label-Of([string]$ref) {
  switch ($ref) {
    'shared_webcontents' { 'HTTP with Microsoft Entra ID - Power Platform API (https://api.powerplatform.com)' }
    'shared_webcontents_storage' { 'HTTP with Microsoft Entra ID - OneLake (https://onelake.dfs.fabric.microsoft.com)' }
    default { $ref }
  }
}

$flowId = [guid]::NewGuid().ToString()
$resources = [ordered]@{}
$apisMap = [ordered]@{}
$connectionsMap = [ordered]@{}
$connectionReferences = [ordered]@{}
$flowDepends = @()
$apiKeys = @{}

foreach ($ref in $refs) {
  $api = Api-Of $ref
  if (-not $apiKeys.ContainsKey($api)) {
    $apiKey = [guid]::NewGuid().ToString()
    $apiKeys[$api] = $apiKey
    $resources[$apiKey] = [ordered]@{
      id = "/providers/Microsoft.PowerApps/apis/$api"; name = $api
      type = 'Microsoft.PowerApps/apis'; suggestedCreationType = 'Existing'
      details = [ordered]@{ displayName = 'HTTP with Microsoft Entra ID (preauthorized)' }
      configurableBy = 'System'; hierarchy = 'Child'; dependsOn = @()
    }
    $flowDepends += $apiKey
  }
  $connKey = [guid]::NewGuid().ToString()
  $resources[$connKey] = [ordered]@{
    type = 'Microsoft.PowerApps/apis/connections'; suggestedCreationType = 'Existing'
    creationType = 'Existing'
    details = [ordered]@{ displayName = (Label-Of $ref) }
    configurableBy = 'User'; hierarchy = 'Child'; dependsOn = @($apiKeys[$api])
  }
  $flowDepends += $connKey
  $apisMap[$ref] = $apiKeys[$api]
  $connectionsMap[$ref] = $connKey
  $connectionReferences[$ref] = [ordered]@{
    connectionName = $connKey; source = 'Invoker'
    id = "/providers/Microsoft.PowerApps/apis/$api"; tier = 'NotSpecified'
  }
}

$resources[$flowId] = [ordered]@{
  type = 'Microsoft.Flow/flows'; suggestedCreationType = 'New'; creationType = 'Existing, New, Update'
  details = [ordered]@{ displayName = $displayName }
  configurableBy = 'User'; hierarchy = 'Root'; dependsOn = $flowDepends
}

$manifest = [ordered]@{
  schema = '1.0'
  details = [ordered]@{
    displayName = $displayName
    description = 'Reads Copilot Studio credits from the Power Platform licensing API daily and writes CSVs to the Consumption Central Lakehouse.'
    createdTime = (Get-Date).ToUniversalTime().ToString('o')
    packageTelemetryId = [guid]::NewGuid().ToString()
    creator = 'Consumption Central'
    sourceEnvironment = ''
  }
  resources = $resources
}

# definition.json: the wrapper is built as text so the definition goes in byte-for-byte.
$propsHead = [ordered]@{
  apiId = '/providers/Microsoft.PowerApps/apis/shared_logicflows'
  displayName = $displayName
  connectionReferences = $connectionReferences
  flowFailureAlertSubscribed = $false
  state = 'Stopped'
} | ConvertTo-Json -Depth 10 -Compress
$definitionJson = '{"name":"' + $flowId + '","id":"/providers/Microsoft.Flow/flows/' + $flowId +
  '","type":"Microsoft.Flow/flows","properties":' + $propsHead.Substring(0, $propsHead.Length - 1) +
  ',"definition":' + $defText + '}}'
$null = $definitionJson | ConvertFrom-Json   # must parse

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $OutFile) { Remove-Item $OutFile }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$zip = [System.IO.Compression.ZipFile]::Open($OutFile, 'Create')
try {
  function Add-Entry([string]$path, [string]$text) {
    # Forward slashes matter: the importer rejects packages zipped with backslash paths.
    $entry = $zip.CreateEntry($path)
    $w = New-Object System.IO.StreamWriter($entry.Open(), $utf8)
    try { $w.Write($text) } finally { $w.Dispose() }
  }
  Add-Entry 'manifest.json' ($manifest | ConvertTo-Json -Depth 10)
  Add-Entry "Microsoft.Flow/flows/manifest.json" ((@{ packageSchemaVersion = '1.0'; flowAssets = @{ assetPaths = @($flowId) } }) | ConvertTo-Json -Depth 5)
  Add-Entry "Microsoft.Flow/flows/$flowId/definition.json" $definitionJson
  Add-Entry "Microsoft.Flow/flows/$flowId/apisMap.json" ($apisMap | ConvertTo-Json -Depth 5)
  Add-Entry "Microsoft.Flow/flows/$flowId/connectionsMap.json" ($connectionsMap | ConvertTo-Json -Depth 5)
} finally { $zip.Dispose() }

Write-Host "Wrote $OutFile"
Write-Host "Connections to pick on import: $($refs -join ', ')"
