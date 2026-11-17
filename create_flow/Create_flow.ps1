<#
.SYNOPSIS
  Wraps the Consumption Central "Copilot Studio credits" flow file into an unmanaged
  Power Platform solution (.zip) for environments that only allow solution import.

.EXAMPLE
  .\Build-StudioFlowSolution.ps1 -FlowFile ".\consumption-central-studio-credits-flow.json"

  Writes ConsumptionCentral-StudioCredits-Solution.zip next to the flow file.
  Works in Windows PowerShell 5.1 and PowerShell 7. Reads only the flow file; sends nothing anywhere.
#>
param(
  [Parameter(Mandatory = $true)][string]$FlowFile,
  [string]$OutFile,
  # Managed by default: environments with the "Unmanaged customizations" rule refuse unmanaged imports.
  [switch]$Unmanaged,
  # Raise this (e.g. 1.0.0.1) to import a fixed version over an earlier one.
  [string]$Version = '1.0.0.0'
)

$ErrorActionPreference = 'Stop'
$FlowFile = (Resolve-Path $FlowFile).Path
if (-not $OutFile) { $OutFile = Join-Path (Split-Path $FlowFile) 'ConsumptionCentral-StudioCredits-Solution.zip' }

$raw = [System.IO.File]::ReadAllText($FlowFile, [System.Text.Encoding]::UTF8)
$file = $raw | ConvertFrom-Json
if (-not $file.definition) { throw "No 'definition' in $FlowFile - is this the installer's flow file?" }
$displayName = if ($file.name) { [string]$file.name } else { 'Consumption Central - Copilot Studio credits' }

# The definition's text exactly as the installer wrote it, so nothing is re-serialised.
$m = [regex]::Match($raw, '"definition"\s*:\s*\{')
if (-not $m.Success) { throw "Couldn't find the definition in $FlowFile." }
$start = $m.Index + $m.Length - 1
$end = $raw.LastIndexOf('}')
$defText = $raw.Substring($start, $end - $start).TrimEnd()
$null = $defText | ConvertFrom-Json

$refs = [regex]::Matches($defText, '"connectionName"\s*:\s*"([^"]+)"') |
  ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
if (-not $refs) { throw 'The definition uses no connections - unexpected.' }

$prefix = 'conscen'   # publisher prefix for this solution's components
$managedFlag = if ($Unmanaged) { 0 } else { 1 }
function Api-Of([string]$ref) { if ($ref -like 'shared_webcontents*') { 'shared_webcontents' } else { $ref } }
function Ref-Info([string]$ref) {
  switch ($ref) {
    'shared_webcontents'         { @{ logical = "${prefix}_ccpowerplatformapi"; label = 'Consumption Central - Power Platform API (https://api.powerplatform.com)' } }
    'shared_webcontents_storage' { @{ logical = "${prefix}_cconelake"; label = 'Consumption Central - OneLake (https://onelake.dfs.fabric.microsoft.com)' } }
    default                      { @{ logical = "${prefix}_" + ($ref -replace '[^A-Za-z0-9]', '').ToLower(); label = $ref } }
  }
}
function Esc([string]$s) { [System.Security.SecurityElement]::Escape($s) }

# Workflow JSON (the flow's clientdata), with each connection bound to a connection reference.
$crJson = ($refs | ForEach-Object {
  $i = Ref-Info $_
  '"' + $_ + '":{"runtimeSource":"embedded","connection":{"connectionReferenceLogicalName":"' + $i.logical + '"},"api":{"name":"' + (Api-Of $_) + '"}}'
}) -join ','
$workflowJson = '{"properties":{"connectionReferences":{' + $crJson + '},"definition":' + $defText + '},"schemaVersion":"1.0.0.0"}'
$null = $workflowJson | ConvertFrom-Json

$flowId = [guid]::NewGuid().ToString()
$jsonName = 'ConsumptionCentral-CopilotStudiocredits-' + $flowId.ToUpper() + '.json'

$connRefXml = ($refs | ForEach-Object {
  $i = Ref-Info $_
@"
    <connectionreference connectionreferencelogicalname="$($i.logical)">
      <connectionreferencedisplayname>$(Esc $i.label)</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/$(Api-Of $_)</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
"@
}) -join "`n"

$customizations = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" OrganizationVersion="9.2.0.0" OrganizationSchemaType="Standard" CRMServerServiceabilityVersion="9.2.0.0">
  <Entities />
  <Roles />
  <Workflows>
    <Workflow WorkflowId="{$flowId}" Name="$(Esc $displayName)">
      <JsonFileName>/Workflows/$jsonName</JsonFileName>
      <Type>1</Type>
      <Subprocess>0</Subprocess>
      <Category>5</Category>
      <Mode>0</Mode>
      <Scope>4</Scope>
      <OnDemand>0</OnDemand>
      <TriggerOnCreate>0</TriggerOnCreate>
      <TriggerOnDelete>0</TriggerOnDelete>
      <AsyncAutodelete>0</AsyncAutodelete>
      <SyncWorkflowLogOnFailure>0</SyncWorkflowLogOnFailure>
      <StateCode>0</StateCode>
      <StatusCode>1</StatusCode>
      <RunAs>1</RunAs>
      <IsTransacted>1</IsTransacted>
      <IntroducedVersion>1.0.0.0</IntroducedVersion>
      <IsCustomizable>1</IsCustomizable>
      <BusinessProcessType>0</BusinessProcessType>
      <IsCustomProcessingStepAllowedForOtherPublishers>1</IsCustomProcessingStepAllowedForOtherPublishers>
      <PrimaryEntity>none</PrimaryEntity>
      <LocalizedNames>
        <LocalizedName languagecode="1033" description="$(Esc $displayName)" />
      </LocalizedNames>
    </Workflow>
  </Workflows>
  <FieldSecurityProfiles />
  <Templates />
  <EntityMaps />
  <EntityRelationships />
  <OrganizationSettings />
  <optionsets />
  <CustomControls />
  <EntityDataProviders />
  <connectionreferences>
$connRefXml
  </connectionreferences>
  <Languages>
    <Language>1033</Language>
  </Languages>
</ImportExportXml>
"@

$solution = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml version="9.2.0.0" SolutionPackageVersion="9.2" languagecode="1033" generatedBy="CrmLive" OrganizationVersion="9.2.0.0" OrganizationSchemaType="Standard" CRMServerServiceabilityVersion="9.2.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <SolutionManifest>
    <UniqueName>ConsumptionCentralStudioCredits</UniqueName>
    <LocalizedNames>
      <LocalizedName description="Consumption Central - Studio Credits" languagecode="1033" />
    </LocalizedNames>
    <Descriptions />
    <Version>$Version</Version>
    <Managed>$managedFlag</Managed>
    <Publisher>
      <UniqueName>ConsumptionCentral</UniqueName>
      <LocalizedNames>
        <LocalizedName description="Consumption Central" languagecode="1033" />
      </LocalizedNames>
      <Descriptions />
      <EMailAddress xsi:nil="true"></EMailAddress>
      <SupportingWebsiteUrl xsi:nil="true"></SupportingWebsiteUrl>
      <CustomizationPrefix>$prefix</CustomizationPrefix>
      <CustomizationOptionValuePrefix>18765</CustomizationOptionValuePrefix>
      <Addresses>
        <Address>
          <AddressNumber>1</AddressNumber>
          <AddressTypeCode>1</AddressTypeCode>
          <ShippingMethodCode>1</ShippingMethodCode>
        </Address>
        <Address>
          <AddressNumber>2</AddressNumber>
          <AddressTypeCode>1</AddressTypeCode>
          <ShippingMethodCode>1</ShippingMethodCode>
        </Address>
      </Addresses>
    </Publisher>
    <RootComponents>
      <RootComponent type="29" id="{$flowId}" behavior="0" />
    </RootComponents>
    <MissingDependencies />
  </SolutionManifest>
</ImportExportXml>
"@

$contentTypes = '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/octet-stream" /><Default Extension="json" ContentType="application/octet-stream" /></Types>'

# Sanity checks: every XML part must parse.
foreach ($x in @($customizations, $solution, $contentTypes)) { $null = [xml]$x }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $OutFile) { Remove-Item $OutFile }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$zip = [System.IO.Compression.ZipFile]::Open($OutFile, 'Create')
try {
  function Add-Entry([string]$path, [string]$text) {
    $entry = $zip.CreateEntry($path)   # forward slashes; the importer rejects backslash paths
    $w = New-Object System.IO.StreamWriter($entry.Open(), $utf8)
    try { $w.Write($text) } finally { $w.Dispose() }
  }
  Add-Entry '[Content_Types].xml' $contentTypes
  Add-Entry 'solution.xml' $solution
  Add-Entry 'customizations.xml' $customizations
  Add-Entry "Workflows/$jsonName" $workflowJson
} finally { $zip.Dispose() }

Write-Host "Wrote $OutFile"
Write-Host "Connection references to bind on import:"
$refs | ForEach-Object { Write-Host "  $((Ref-Info $_).label)" }
