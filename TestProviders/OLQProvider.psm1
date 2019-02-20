##############################################################################################
# OLProvider.psm1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
	PS modules for LISAv2 test automation
	This module provides the test operations on OL

.PARAMETER
	<Parameters>

.INPUTS


.NOTES
	Creation Date:
	Purpose/Change:

.EXAMPLE


#>
###############################################################################################
using Module ".\TestProvider.psm1"
using Module ".\AzureProvider.psm1"
using Module "..\Libraries\CommonFunctions.psm1"

Class OLQProvider : AzureProvider
{
    [String] $HostFwdPort
    [string] $OLUserName
    [string] $OLUserPassword
    [string] $OLImageUrl
    [string] $OLImageName

    [object] DeployVMs([xml] $GlobalConfig, [object] $SetupTypeData, [object] $TestCaseData, [string] $TestLocation, [string] $RGIdentifier, [bool] $UseExistingRG) {
        $allVMData = ([AzureProvider]$this).DeployVMs($GlobalConfig, $SetupTypeData, $TestCaseData, $TestLocation, $RGIdentifier, $UseExistingRG)

        if ($($GlobalConfig.Global.OL.TestCredentials)) {
            $this.OLUserName = $($GlobalConfig.Global.OL.TestCredentials.OLUserName)
            $this.OLUserPassword = $($GlobalConfig.Global.OL.TestCredentials.OLUserPassword)
            $this.OLImageUrl = $($GlobalConfig.Global.OL.TestCredentials.OLImageUrl)
            $this.OLImageName = $($GlobalConfig.Global.OL.TestCredentials.OLImageName)
            $this.HostFwdPort = $($GlobalConfig.Global.OL.TestCredentials.HostFwdPort)
        } else {
            Write-LogErr "Cannnot find test credentials for OL platform"
            throw "OL credentials missing"
        }

        Write-LogInfo "Setting up inBound NAT Rule for port : $($this.HostFwdPort)"
        $azureLB = Get-AzureRmLoadBalancer -ResourceGroupName $allVMData.ResourceGroupName
        $azureLB | Add-AzureRmLoadBalancerInboundNatRuleConfig -Name "NewNatRule" -FrontendIPConfiguration $AzureLB.FrontendIpConfigurations[0] `
        -Protocol "Tcp" -FrontendPort $($this.HostFwdPort) -BackendPort $($this.HostFwdPort)

        $nicName=(Get-AzureRmNetworkInterface -ResourceGroupName $allVMData.ResourceGroupName ).Name
        $nic = Get-AzureRmNetworkInterface -ResourceGroupName $allVMData.ResourceGroupName -Name $nicName
        $nic.IpConfigurations[0].LoadBalancerInboundNatRules.Add($azureLB.InboundNatRules[1])
        $azureLB | Set-AzureRmLoadBalancer

        Set-AzureRmNetworkInterface -NetworkInterface $nic

        Copy-RemoteFiles -upload -uploadTo $allVMData.PublicIP -Port $allVMData.SSHPort `
        -files ".\TestScripts\Linux\deploy_ol_vm.sh,Testscripts\Linux\utils.sh" -Username $global:user -password $global:password

        $cmdResult = Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort -Username $global:user -password $global:password `
        -command "bash ./deploy_ol_vm.sh -OLImageUrl $($this.OLImageUrl) -OLip $($allVMData.InternalIP) -HostFwdPort $($this.HostFwdPort) -OLUser $($this.OLUserName) -OLUserPassword $($this.OLUserPassword) -OLImageName $($this.OLImageName)" `
        -runAsSudo -runMaxAllowedTime 2000

        if (-not $cmdResult) {
            Write-LogErr "Fail to Deploy OL VM"
            throw "error"
        } else {
            Write-LogInfo "Sucesfully deployed OL VM"
            $allVMData.SSHPort = $this.HostFwdPort
        }
        Set-Variable -Name user -Value $this.OLUserName -Scope Global -Force
        Set-Variable -Name password -Value $this.OLUserPassword -Scope Global -Force
        return $allVMData
    }

    [bool] RestartAllDeployments($allVMData) {
        #Currenlty reboot is not supported
        return $true
    }
}