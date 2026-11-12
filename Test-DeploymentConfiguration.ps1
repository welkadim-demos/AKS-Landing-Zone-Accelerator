[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $NetworkParametersFile,
    [Parameter(Mandatory)]
    [string] $AKSParametersFile
)

$ErrorActionPreference = 'Stop'

function Read-DeploymentParameters {
    param([string] $Path)

    if ([IO.Path]::GetExtension($Path) -eq '.json') {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable).parameters
    }

    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "aks-parameters-$([guid]::NewGuid()).json"
    try {
        az bicep build-params --file $Path --outfile $outputPath
        if ($LASTEXITCODE -ne 0) {
            throw "Could not compile parameter file: $Path"
        }
        return (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -AsHashtable).parameters
    }
    finally {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath
        }
    }
}

$network = Read-DeploymentParameters $NetworkParametersFile
$aks = Read-DeploymentParameters $AKSParametersFile
$networkPlugin = $aks.ContainsKey('aksNetworkPlugin') ? $aks.aksNetworkPlugin.value : 'azure'
if ($networkPlugin -ne 'azure') {
    throw "aksNetworkPlugin must be 'azure' (Azure CNI). Kubenet is not supported because it retires in March 2028."
}
$supportPlan = $aks.ContainsKey('aksSupportPlan') ? $aks.aksSupportPlan.value : 'KubernetesOfficial'
$skuTier = $aks.ContainsKey('skuTier') ? $aks.skuTier.value : 'Standard'
if ($supportPlan -eq 'AKSLongTermSupport' -and $skuTier -ne 'Premium') {
    throw 'AKSLongTermSupport requires skuTier = Premium.'
}
$connectToHub = $network.ContainsKey('connectToHub') ? $network.connectToHub.value : $true
$outboundType = $aks.ContainsKey('aksOutboundType') ? $aks.aksOutboundType.value : 'loadBalancer'
$firewallIP = $network.ContainsKey('firewallIP') ? $network.firewallIP.value : ''
$useFirewall = ![string]::IsNullOrEmpty($firewallIP)

if ($connectToHub) {
    foreach ($name in @('hubSubscriptionId', 'hubResourceGroupName', 'hubVnetName')) {
        if ([string]::IsNullOrWhiteSpace($network[$name].value)) {
            throw "Hub-connected networking requires $name. Set it or use connectToHub = false."
        }
    }
}
if ($useFirewall) {
    if (!$connectToHub) {
        throw 'firewallIP requires connectToHub = true. Omit firewallIP for standalone networking.'
    }
    $firewallAddress = $null
    if (![IPAddress]::TryParse($firewallIP, [ref] $firewallAddress) -or
        $firewallAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'firewallIP must be an IPv4 address.'
    }
}

$expectedOutboundType = $useFirewall ? 'userDefinedRouting' : 'loadBalancer'
if ($outboundType -ne $expectedOutboundType) {
    throw "connectToHub = $connectToHub, useFirewall = $useFirewall requires aksOutboundType = '$expectedOutboundType'; found '$outboundType'."
}

$expectedAKSSubnetName = $network.ContainsKey('aksSubnetName') ? $network.aksSubnetName.value : 'AKS'
$deployApplicationGateway = $network.ContainsKey('deployApplicationGateway') ? $network.deployApplicationGateway.value : $true
$enableIngressApplicationGateway = $aks.ContainsKey('enableIngressApplicationGateway') ? $aks.enableIngressApplicationGateway.value : $true
if ($enableIngressApplicationGateway -and !$deployApplicationGateway) {
    throw 'enableIngressApplicationGateway requires deployApplicationGateway = true.'
}
$subnetNames = @($network.vnetSpokeSubnets.value | ForEach-Object { $_.name })
$requiredSubnetNames = @($expectedAKSSubnetName)
if ($deployApplicationGateway) {
    $requiredSubnetNames += $network.appgwsubnetName.value
}
foreach ($name in $requiredSubnetNames) {
    if ([string]::IsNullOrWhiteSpace($name) -or $name -notin $subnetNames) {
        throw "The network subnet list must contain '$name' for its NSG and route-table associations."
    }
}
if ($deployApplicationGateway -and $expectedAKSSubnetName -eq $network.appgwsubnetName.value) {
    throw 'AKS and Application Gateway must use separate subnets.'
}

$namePairs = @(
    @('rgName', 'vnetspokeRGName'),
    @('vnteSpokeName', 'aksvnetName'),
    @('rtAKSSubnetname', 'rtaksName')
)
if ($deployApplicationGateway) {
    $namePairs += ,@('appgwName', 'aksAppGatewayName')
}
foreach ($pair in $namePairs) {
    if ([string]::IsNullOrWhiteSpace($network[$pair[0]].value) -or
        $network[$pair[0]].value -ne $aks[$pair[1]].value) {
        throw "Network $($pair[0]) must match AKS $($pair[1])."
    }
}
if ($expectedAKSSubnetName -ne $aks.akssubnetName.value) {
    throw 'Network aksSubnetName must match AKS akssubnetName.'
}

Write-Host "Configuration valid: connectToHub=$connectToHub, useFirewall=$useFirewall, aksOutboundType=$outboundType."
