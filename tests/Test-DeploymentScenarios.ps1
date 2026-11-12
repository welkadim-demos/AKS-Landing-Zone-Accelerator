[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $BicepPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) "aks-scenarios-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
$testEnvironment = @{
    HUB_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000000'
    DNS_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000000'
    AKS_ADMIN_GROUP_ID = '00000000-0000-0000-0000-000000000001'
    AKS_USERS_GROUP_ID = '00000000-0000-0000-0000-000000000002'
    AKS_KUBERNETES_VERSION = '1.35.1'
    SPOKE_VNET_RESOURCE_ID = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-spoke-dev-uksouth-01/providers/Microsoft.Network/virtualNetworks/vnet-spoke-dev-uksouth-01'
}
$previousEnvironment = @{}
$compiledParameters = @{}

function Compile-Parameters {
    param([string] $RelativePath, [string] $Name)
    if ($compiledParameters.ContainsKey($RelativePath)) {
        return $compiledParameters[$RelativePath]
    }
    $outputPath = Join-Path $temporaryDirectory "$Name.json"
    & $BicepPath build-params (Join-Path $root $RelativePath) --outfile $outputPath
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $RelativePath" }
    $compiledParameters[$RelativePath] = $outputPath
    return $outputPath
}

function Expect-Failure {
    param([scriptblock] $Action, [string] $Message)
    $failed = $false
    try { & $Action }
    catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $failed = $true
    }
    if (!$failed) { throw "Expected validation failure: $Message" }
    Write-Host "PASS: rejects $Message"
}

function Compile-Template {
    param([string] $RelativePath)
    $json = & $BicepPath build (Join-Path $root $RelativePath) --stdout
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $RelativePath" }
    return $json | ConvertFrom-Json -AsHashtable
}

function Assert-DisabledResources {
    param($Template, $Parameters, [string[]] $ResourceNames)
    foreach ($name in $ResourceNames) {
        $resource = if ($Template.resources -is [System.Collections.IDictionary]) {
            $Template.resources[$name]
        }
        else {
            $Template.resources | Where-Object name -EQ $name
        }
        $condition = $resource.condition
        if ($condition -notmatch "^\[parameters\('([^']+)'\)\]$" -or
            !$Parameters.ContainsKey($Matches[1]) -or
            $Parameters[$Matches[1]].value -ne $false) {
            throw "Minimal scenario must suppress resource: $name"
        }
    }
}

try {
    foreach ($name in $testEnvironment.Keys) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $testEnvironment[$name], 'Process')
    }
    $validator = Join-Path $root 'Test-DeploymentConfiguration.ps1'
    $hubNetwork = Compile-Parameters 'environments\dev\03-Network-LZ\main.bicepparam' 'hub-network'
    $hubAKS = Compile-Parameters 'environments\dev\05-AKS\main.bicepparam' 'hub-aks'
    $standaloneNetwork = Compile-Parameters 'environments\standalone\03-Network-LZ\main.bicepparam' 'standalone-network'
    $standaloneAKS = Compile-Parameters 'environments\standalone\05-AKS\main.bicepparam' 'standalone-aks'
    & $validator -NetworkParametersFile $hubNetwork -AKSParametersFile $hubAKS
    & $validator -NetworkParametersFile $standaloneNetwork -AKSParametersFile $standaloneAKS

    $invalidPluginAKS = Get-Content -LiteralPath $hubAKS -Raw | ConvertFrom-Json -AsHashtable
    $invalidPluginPath = Join-Path $temporaryDirectory 'invalid-plugin-aks.json'
    foreach ($plugin in @('kubenet', 'kebenet')) {
        $invalidPluginAKS.parameters.aksNetworkPlugin.value = $plugin
        $invalidPluginAKS | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPluginPath
        Expect-Failure { & $validator -NetworkParametersFile $hubNetwork -AKSParametersFile $invalidPluginPath } "aksNetworkPlugin must be 'azure'"
    }
    $invalidPluginAKS.parameters.Remove('aksNetworkPlugin')
    $invalidPluginAKS | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPluginPath
    & $validator -NetworkParametersFile $hubNetwork -AKSParametersFile $invalidPluginPath

    Expect-Failure { & $validator -NetworkParametersFile $hubNetwork -AKSParametersFile $standaloneAKS } 'userDefinedRouting'
    Expect-Failure { & $validator -NetworkParametersFile $standaloneNetwork -AKSParametersFile $hubAKS } 'loadBalancer'

    $invalidNetwork = Get-Content -LiteralPath $hubNetwork -Raw | ConvertFrom-Json -AsHashtable
    $invalidNetwork.parameters.Remove('firewallIP')
    $invalidPath = Join-Path $temporaryDirectory 'invalid.json'
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $hubAKS } 'loadBalancer'

    $noFirewallAKS = Get-Content -LiteralPath $hubAKS -Raw | ConvertFrom-Json -AsHashtable
    $noFirewallAKS.parameters.aksOutboundType.value = 'loadBalancer'
    $noFirewallAKSPath = Join-Path $temporaryDirectory 'no-firewall-aks.json'
    $noFirewallAKS | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $noFirewallAKSPath
    & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $noFirewallAKSPath

    $invalidNetwork.parameters.firewallIP = @{ value = '' }
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $noFirewallAKSPath

    $invalidNetwork.parameters.firewallIP.value = ' '
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $noFirewallAKSPath } 'must be an IPv4 address'

    $invalidNetwork.parameters.Remove('hubVnetName')
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $noFirewallAKSPath } 'requires hubVnetName'

    $invalidNetwork = Get-Content -LiteralPath $standaloneNetwork -Raw | ConvertFrom-Json -AsHashtable
    $invalidNetwork.parameters.firewallIP = @{ value = '10.0.1.4' }
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $standaloneAKS } 'firewallIP requires connectToHub'

    $invalidNetwork = Get-Content -LiteralPath $standaloneNetwork -Raw | ConvertFrom-Json -AsHashtable
    $invalidNetwork.parameters.vnetSpokeSubnets.value = @(
        $invalidNetwork.parameters.vnetSpokeSubnets.value | Where-Object name -NE 'AKS'
    )
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $standaloneAKS } "must contain 'AKS'"

    $invalidNetwork = Get-Content -LiteralPath $standaloneNetwork -Raw | ConvertFrom-Json -AsHashtable
    $invalidNetwork.parameters.rtAKSSubnetname.value = 'wrong-route-table'
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $standaloneAKS } 'rtAKSSubnetname must match'

    $minimalNetwork = Compile-Parameters 'environments\minimal\03-Network-LZ\main.bicepparam' 'minimal-network'
    $minimalAKS = Compile-Parameters 'environments\minimal\05-AKS\main.bicepparam' 'minimal-aks'
    & $validator -NetworkParametersFile $minimalNetwork -AKSParametersFile $minimalAKS

    $nonPremiumAKS = Get-Content -LiteralPath $minimalAKS -Raw | ConvertFrom-Json -AsHashtable
    $nonPremiumAKS.parameters.skuTier.value = 'Standard'
    $nonPremiumPath = Join-Path $temporaryDirectory 'non-premium-aks.json'
    $nonPremiumAKS | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $nonPremiumPath
    Expect-Failure { & $validator -NetworkParametersFile $minimalNetwork -AKSParametersFile $nonPremiumPath } 'requires skuTier = Premium'
    $nonPremiumAKS.parameters.Remove('skuTier')
    $nonPremiumAKS | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $nonPremiumPath
    Expect-Failure { & $validator -NetworkParametersFile $minimalNetwork -AKSParametersFile $nonPremiumPath } 'requires skuTier = Premium'

    $invalidNetwork = Get-Content -LiteralPath $minimalNetwork -Raw | ConvertFrom-Json -AsHashtable
    foreach ($name in @('appgwsubnetName', 'appgwName', 'appgwroutetableName')) {
        $invalidNetwork.parameters.Remove($name)
    }
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $minimalAKS

    $invalidAKS = Get-Content -LiteralPath $minimalAKS -Raw | ConvertFrom-Json -AsHashtable
    $invalidAKS.parameters.enableIngressApplicationGateway.value = $true
    $invalidAKSPath = Join-Path $temporaryDirectory 'invalid-aks.json'
    $invalidAKS | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidAKSPath
    Expect-Failure { & $validator -NetworkParametersFile $minimalNetwork -AKSParametersFile $invalidAKSPath } 'requires deployApplicationGateway'

    $invalidNetwork.parameters.deployApplicationGateway.value = $true
    $invalidNetwork.parameters.appgwsubnetName = @{ value = 'AppGWSubnet' }
    $invalidNetwork | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPath
    Expect-Failure { & $validator -NetworkParametersFile $invalidPath -AKSParametersFile $minimalAKS } "must contain 'AppGWSubnet'"

    $hubPath = Compile-Parameters 'environments\minimal\02-Network-Hub\main.bicepparam' 'minimal-hub'
    $hub = (Get-Content -LiteralPath $hubPath -Raw | ConvertFrom-Json -AsHashtable).parameters
    if ($hub.hubSubnets.value.Count -ne 1) { throw 'Minimal hub must have exactly one subnet.' }
    Assert-DisabledResources (Compile-Template '02-Network-Hub\main.bicep') $hub @(
        'azfirewall', 'firewallPolicy', 'aksIpGroup', 'bastion', 'routetable'
    )

    $dnsPath = Compile-Parameters 'environments\minimal\03-0-DNSZones\main.bicepparam' 'minimal-dns'
    $dns = (Get-Content -LiteralPath $dnsPath -Raw | ConvertFrom-Json -AsHashtable).parameters
    $dnsTemplate = Compile-Template '03-0-DNSZones\main.bicep'
    Assert-DisabledResources $dnsTemplate $dns @('privatednsPostgreSQLZone', 'privatednsManagedRedisZone', 'privatednsACRZone', 'privatednsvalutZone')

    $network = (Get-Content -LiteralPath $minimalNetwork -Raw | ConvertFrom-Json -AsHashtable).parameters
    Assert-DisabledResources (Compile-Template '03-Network-LZ\main.bicep') $network @(
        'appgw', 'publicipappgw', 'nsgAppGw', 'appgwroutetable'
    )

    $supportingPath = Compile-Parameters 'environments\minimal\04-AKS-Supporting\main.bicepparam' 'minimal-supporting'
    $supporting = (Get-Content -LiteralPath $supportingPath -Raw | ConvertFrom-Json -AsHashtable).parameters
    $supportingTemplate = Compile-Template '04-AKS-Supporting\main.bicep'
    Assert-DisabledResources $supportingTemplate $supporting @('acr', 'keyvault')
    if (@($supporting.storageAccountNames.value | Select-Object -Unique).Count -ne 2 -or
        $supporting.storageAccountNames.value.Count -ne 2 -or
        $supporting.storagePublicNetworkAccess.value -ne 'Disabled' -or
        $supportingTemplate.resources.storage.copy.count -ne "[length(variables('accountNames'))]" -or
        $supportingTemplate.variables.accountNames -ne "[coalesce(parameters('storageAccountNames'), createArray(parameters('storageAccountName')))]") {
        throw 'Minimal supporting stage must deploy exactly two private storage accounts.'
    }
    $services = @('blob', 'file')
    if ($supporting.storageAccountType.value -ne 'Standard_ZRS' -or
        $supportingTemplate.parameters.storageAllowSharedKeyAccess.defaultValue -ne $false) {
        throw 'Minimal storage must be zone redundant and default to Microsoft Entra authentication only.'
    }
    $spokeSubnets = @($network.vnetSpokeSubnets.value)
    if (@($spokeSubnets | Where-Object { $_.defaultOutboundAccess -ne $false }).Count -or
        $network.privateEndpointAllowedSourcePrefixes.value.Count -ne 1) {
        throw 'Minimal spoke subnets must be private (no default outbound access) and restrict the private endpoint subnet to the AKS subnet.'
    }
    $linksPath = Compile-Parameters 'environments\minimal\03-0-DNSZones\links.bicepparam' 'minimal-links'
    $linkParameters = (Get-Content -LiteralPath $linksPath -Raw | ConvertFrom-Json -AsHashtable).parameters
    if ((Compare-Object $services $supporting.storagePrivateEndpointServices.value) -or
        (Compare-Object $services $dns.storageServices.value) -or
        (Compare-Object $services $linkParameters.storageServices.value) -or
        $supportingTemplate.resources.storage.properties.parameters.privateEndpoints.copy[0].count -ne
            "[length(parameters('storagePrivateEndpointServices'))]") {
        throw 'Private endpoints, DNS zones and DNS links must use the same storage services (blob and file).'
    }
    foreach ($template in @($supportingTemplate, $dnsTemplate, (Compile-Template '03-0-DNSZones\links.bicep'))) {
        if (($template | ConvertTo-Json -Depth 30) -match "'web'|\.web\.") {
            throw 'Static website (web) private endpoints and zones are not supported.'
        }
    }

    $aks = (Get-Content -LiteralPath $minimalAKS -Raw | ConvertFrom-Json -AsHashtable).parameters
    $aksTemplate = Compile-Template '05-AKS\main.bicep'
    Assert-DisabledResources $aksTemplate $aks @(
        'acraksaccess', 'keyvaultAccessPolicy', 'appGateway',
        'appGatewayContributorRole', 'appGatewayReaderRole'
    )
    $cluster = $aksTemplate.resources.aks.properties.parameters
    if ($aks.aksNetworkDataplane.value -ne 'azure' -or $aks.aksNetworkPolicy.value -ne 'azure' -or
        $aks.aksUpgradeChannel.value -ne 'none' -or $aks.aksNodeOSUpgradeChannel.value -ne 'NodeImage' -or
        $cluster.autoUpgradeProfile.value.upgradeChannel -ne "[variables('effectiveUpgradeChannel')]" -or
        $cluster.autoUpgradeProfile.value.nodeOSUpgradeChannel -ne "[parameters('aksNodeOSUpgradeChannel')]" -or
        $cluster.nodeResourceGroupProfile.value.restrictionLevel -ne 'ReadOnly' -or
        $cluster.maintenanceConfigurations.value -notlike "*maintenanceConfigurations*") {
        throw 'Minimal AKS must use Azure network policy, manual Kubernetes upgrades with managed node image updates, a read-only node resource group and maintenance windows.'
    }
    if ($cluster.azurePolicyEnabled.value -ne "[parameters('enableAzurePolicy')]" -or
        @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.bicep' -File |
            Where-Object { $_.FullName -notmatch '\\(Samples|\.github)\\' } |
            Select-String -Pattern 'Microsoft\.Authorization/policyAssignments').Count) {
        throw 'AKS must use only the Azure Policy add-on; no policy assignments may be deployed.'
    }
    foreach ($stage in @($hub, $network, $supporting, $aks)) {
        if ($stage.logAnalyticsWorkspaceResourceId.value -ne '') {
            throw 'Log Analytics diagnostics must be off unless LOG_ANALYTICS_WORKSPACE_ID is set.'
        }
    }
    $additionalPools = $aks.additionalNodePools.value
    $poolCopy = $cluster.agentPools.copy[0]
    if (($cluster.primaryAgentPoolProfiles.value.Count + $additionalPools.Count) -ne 3 -or
        $poolCopy.count -ne "[length(parameters('additionalNodePools'))]" -or
        !$poolCopy.input.StartsWith("[union(createObject('availabilityZones', parameters('availabilityZones'), 'vnetSubnetResourceId', ") -or
        !$poolCopy.input.EndsWith(", parameters('additionalNodePools')[copyIndex('value')])]") -or
        !$cluster.apiServerAccessProfile.value.enablePrivateCluster -or
        $cluster.outboundType.value -ne "[parameters('aksOutboundType')]" -or
        $aks.aksOutboundType.value -ne 'loadBalancer' -or
        $cluster.enableKeyvaultSecretsProvider.value -ne "[parameters('enableKeyVaultIntegration')]" -or
        $cluster.webApplicationRoutingEnabled.value -ne "[parameters('aksEnableWebRoutingAddOn')]" -or
        $aks.aksEnableWebRoutingAddOn.value -ne $false) {
        throw 'Minimal AKS must remain private with three pools, Load Balancer egress and no ingress/Key Vault add-ons.'
    }
    $systemPool = $cluster.primaryAgentPoolProfiles.value[0]
    if ($systemPool.vmSize -ne "[parameters('aksSystemPoolVMSize')]" -or
        $systemPool.count -ne "[parameters('aksSystemPoolNodesCount')]" -or
        $aks.aksSystemPoolVMSize.value -ne 'Standard_D16ads_v6' -or
        $aks.aksSystemPoolNodesCount.value -ne 3 -or
        $systemPool.osDiskType -ne "[parameters('aksSystemPoolOSDiskType')]" -or
        $aks.aksSystemPoolOSDiskType.value -ne 'Ephemeral' -or
        $systemPool.osDiskSizeGB -ne "[parameters('aksSystemPoolOSDiskSizeGB')]" -or
        $aks.aksSystemPoolOSDiskSizeGB.value -ne 128 -or
        $systemPool.availabilityZones -ne "[parameters('availabilityZones')]" -or
        (Compare-Object @(2, 3) $aks.availabilityZones.value)) {
        throw 'Minimal system pool must use three D16ads v6 nodes with 128 GiB ephemeral OS disks in zones 2 and 3.'
    }
    $expectedPools = @(
        @{ Pool = $additionalPools[0]; Name = 'burst'; ExpectedSize = 'Standard_D32ads_v6'; ExpectedCount = 1 },
        @{ Pool = $additionalPools[1]; Name = 'burstmemory'; ExpectedSize = 'Standard_E32ads_v6'; ExpectedCount = 1 }
    )
    foreach ($expected in $expectedPools) {
        if ($expected.Pool.name -ne $expected.Name -or
            $expected.Pool.vmSize -ne $expected.ExpectedSize -or
            $expected.Pool.count -ne $expected.ExpectedCount -or
            $expected.Pool.mode -ne 'User' -or
            $expected.Pool.osDiskType -ne 'Ephemeral' -or
            $expected.Pool.enableEncryptionAtHost -ne $true) {
            throw "Minimal pool $($expected.Pool.name) must use $($expected.ExpectedCount) x $($expected.ExpectedSize) with ephemeral OS disks."
        }
    }
    if ($cluster.supportPlan.value -ne "[parameters('aksSupportPlan')]" -or
        $aks.aksSupportPlan.value -ne 'AKSLongTermSupport' -or
        $cluster.skuTier.value -ne "[parameters('skuTier')]" -or
        $aks.skuTier.value -ne 'Premium' -or
        $cluster.kubernetesVersion.value -ne "[parameters('kubernetesVersion')]" -or
        $aks.kubernetesVersion.value -ne '1.36.5') {
        throw 'Minimal AKS must use the regional default LTS-capable patch with Premium tier.'
    }
    $spotPool = $additionalPools[0]
    if ($spotPool.scaleSetPriority -ne 'Spot' -or
        $spotPool.scaleSetEvictionPolicy -ne 'Delete' -or
        $spotPool.spotMaxPrice -ne -1 -or
        $spotPool.nodeLabels.'kubernetes.azure.com/scalesetpriority' -ne 'spot' -or
        'kubernetes.azure.com/scalesetpriority=spot:NoSchedule' -notin $spotPool.nodeTaints -or
        $spotPool.enableAutoScaling -ne $true -or
        $aks.aksSystemPoolNodeMin.value -ne 3 -or $aks.aksSystemPoolNodeMax.value -ne 3 -or
        $spotPool.minCount -ne 0 -or $spotPool.maxCount -ne 1) {
        throw 'Minimal Spot pool must be isolated with Delete eviction and scale between 0 and 1 nodes.'
    }
    $memoryPool = $additionalPools[1]
    if ($aks.aksSystemPoolName.value -ne 'base' -or
        $systemPool.name -ne "[parameters('aksSystemPoolName')]" -or
        $spotPool.osDiskSizeGB -ne 60 -or $memoryPool.osDiskSizeGB -ne 128 -or
        $memoryPool.enableAutoScaling -ne $true -or $memoryPool.minCount -ne 0 -or
        $memoryPool.nodeLabels.workload -ne 'burst-memory' -or
        'workload=burst-memory:NoSchedule' -notin $memoryPool.nodeTaints -or
        $memoryPool.tags.lifecycle -ne 'temporary' -or
        $memoryPool.tags.expiresOn -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw 'Minimal pools must be base (system + application), burst (Spot) and a tainted temporary burstmemory pool with an expiry tag.'
    }
    foreach ($stage in @($hub, $dns, $network, $supporting, $aks, $linkParameters)) {
        if ($stage.location.value -ne 'swedencentral') { throw 'Every minimal stage must use Sweden Central.' }
    }
    if ($network.hubResourceGroupName.value -ne $hub.rgName.value -or
        $network.hubVnetName.value -ne $hub.vnetHubName.value -or
        $supporting.rgSpokevnetName.value -ne $network.rgName.value -or
        $supporting.vnetSpokeName.value -ne $network.vnteSpokeName.value) {
        throw 'Minimal cross-stage names must match after changing region.'
    }
    Write-Host 'PASS: Sweden Central minimal uses Premium LTS 1.36.5 with 3 x D16ads v6, 1 x Spot D32ads v6 and 1 x E32ads v6, all with ephemeral OS disks in zones 2 and 3.'
    Write-Host 'PASS: minimal resource gates, two accounts, four storage endpoints, DNS coverage and private three-pool AKS.'

    Get-ChildItem -LiteralPath (Join-Path $root 'environments') -Recurse -Filter '*.bicepparam' -File | ForEach-Object {
        $relativePath = [IO.Path]::GetRelativePath($root, $_.FullName)
        $name = $relativePath -replace '[\\/]', '-'
        [void](Compile-Parameters $relativePath $name)
    }
    Write-Host "PASS: all $($compiledParameters.Count) environment parameter files compile."

    $runbook = Get-Content -LiteralPath (Join-Path $root 'deployment.azcli') -Raw
    $azureCalls = [System.Collections.Generic.List[object]]::new()
    $mockSubscriptionId = $testEnvironment.HUB_SUBSCRIPTION_ID
    $mockFeatureState = 'Registered'
    $mockVnetId = $testEnvironment.SPOKE_VNET_RESOURCE_ID
    function az {
        $arguments = @($args)
        $global:LASTEXITCODE = 0
        $command = $arguments[0..1] -join ' '
        if ($command -eq 'bicep build-params') {
            $file = $arguments[[Array]::IndexOf($arguments, '--file') + 1]
            $output = $arguments[[Array]::IndexOf($arguments, '--outfile') + 1]
            & $BicepPath build-params $file --outfile $output
            return
        }
        $azureCalls.Add([pscustomobject]@{ Arguments = $arguments })
        switch ($command) {
            'account show' { return $mockSubscriptionId }
            'feature show' { return $mockFeatureState }
            'provider register' { return }
            'network vnet' { return $mockVnetId }
            'deployment sub' {
                if ($arguments[2] -eq 'show') { return $mockVnetId }
                if ($arguments[2] -eq 'create') { return }
                throw "Unexpected deployment operation: $($arguments[2])"
            }
            default { throw "Unexpected Azure command: $command" }
        }
    }

    Push-Location $root
    try {
        foreach ($profile in @('minimal', 'dev', 'standalone')) {
            $azureCalls.Clear()
            $script = $runbook.Replace('$environment = ''minimal''', "`$environment = '$profile'")
            & ([scriptblock]::Create($script))
            $deployments = @($azureCalls | Where-Object { ($_.Arguments[0..2] -join ' ') -eq 'deployment sub create' })
            $expectedStages = @(
                '02-0-Monitoring\main.bicepparam',
                '03-0-DNSZones\main.bicepparam', '03-Network-LZ\main.bicepparam',
                '03-0-DNSZones\links.bicepparam', '04-AKS-Supporting\main.bicepparam',
                '05-AKS\main.bicepparam'
            )
            if ($profile -ne 'standalone') {
                $expectedStages = @($expectedStages[0], '02-Network-Hub\main.bicepparam') + $expectedStages[1..($expectedStages.Count - 1)]
            }
            if ($deployments.Count -ne $expectedStages.Count) { throw "Unexpected deployment count for $profile." }
            for ($i = 0; $i -lt $expectedStages.Count; $i++) {
                $arguments = $deployments[$i].Arguments
                $path = $arguments[[Array]::IndexOf($arguments, '--parameters') + 1]
                $subscription = $arguments[[Array]::IndexOf($arguments, '--subscription') + 1]
                $location = $arguments[[Array]::IndexOf($arguments, '--location') + 1]
                $expectedLocation = if ($profile -eq 'minimal') { 'swedencentral' } else { 'uksouth' }
                if ($path -ne ".\environments\$profile\$($expectedStages[$i])" -or
                    $subscription -ne $mockSubscriptionId -or
                    $location -ne $expectedLocation -or
                    '--confirm-with-what-if' -notin $arguments) {
                    throw "Runbook must deploy the $profile stages in order, to the active subscription, with approval."
                }
            }
            Write-Host "PASS: $profile runbook selects the correct stages and active subscription with What-If approval."
        }

        $otherHubSubscription = '11111111-1111-1111-1111-111111111111'
        foreach ($deployHubValue in @('$true', '$false')) {
            $azureCalls.Clear()
            $env:AKS_HUB_SUBSCRIPTION_ID = $otherHubSubscription
            $script = $runbook.Replace('$deployHub = $true', "`$deployHub = $deployHubValue")
            & ([scriptblock]::Create($script))
            Remove-Item Env:AKS_HUB_SUBSCRIPTION_ID
            $deployments = @($azureCalls | Where-Object { ($_.Arguments[0..2] -join ' ') -eq 'deployment sub create' })
            $hubDeployments = @($deployments | Where-Object { ($_.Arguments -join ' ') -like '*02-Network-Hub*' })
            $otherDeployments = @($deployments | Where-Object { ($_.Arguments -join ' ') -notlike '*02-Network-Hub*' })
            $vnetChecks = @($azureCalls | Where-Object { ($_.Arguments[0..1] -join ' ') -eq 'network vnet' })
            $hubSubscriptionOk = if ($deployHubValue -eq '$true') {
                $hubDeployments.Count -eq 1 -and
                    $hubDeployments[0].Arguments[[Array]::IndexOf($hubDeployments[0].Arguments, '--subscription') + 1] -eq $otherHubSubscription -and
                    $vnetChecks.Count -eq 0
            }
            else {
                $hubDeployments.Count -eq 0 -and $vnetChecks.Count -eq 1 -and
                    $vnetChecks[0].Arguments[[Array]::IndexOf($vnetChecks[0].Arguments, '--subscription') + 1] -eq $otherHubSubscription
            }
            $workloadOk = -not ($otherDeployments | Where-Object {
                $_.Arguments[[Array]::IndexOf($_.Arguments, '--subscription') + 1] -ne $mockSubscriptionId
            })
            if (-not $hubSubscriptionOk -or -not $workloadOk) {
                throw "Hub in another subscription (deployHub = $deployHubValue) must target only the hub subscription for hub work."
            }
        }
        Write-Host 'PASS: hub in another subscription is deployed or reused, with workload stages in the active subscription.'

        $azureCalls.Clear()
        $mockFeatureState = 'Registering'
        Expect-Failure { & ([scriptblock]::Create($runbook)) } 'EncryptionAtHost'
        if ($azureCalls | Where-Object { ($_.Arguments[0..2] -join ' ') -eq 'deployment sub create' }) {
            throw 'Runbook must not deploy before EncryptionAtHost is registered.'
        }
        $mockFeatureState = 'Registered'
        $mockSubscriptionId = ''
        Expect-Failure { & ([scriptblock]::Create($runbook)) } 'No active subscription'
    }
    finally {
        Pop-Location
    }

    Write-Host 'All deployment configuration tests passed.'
}
finally {
    Remove-Item Env:LOG_ANALYTICS_WORKSPACE_ID -ErrorAction SilentlyContinue
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    Get-ChildItem -LiteralPath $temporaryDirectory -File | Remove-Item
    Remove-Item -LiteralPath $temporaryDirectory
}
