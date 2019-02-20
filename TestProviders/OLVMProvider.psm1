##############################################################################################
# OLVMProvider.psm1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
	PS modules for LISAv2 test automation
	This module provides the test operations on OL and create VM from VHD provided

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

Class OLVMProvider : AzureProvider
{
	[string] $OLUserName
	[string] $OLUserPassword

	[object] DeployVMs([xml] $GlobalConfig, [object] $SetupTypeData, [object] $TestCaseData, [string] $TestLocation, [string] $RGIdentifier, [bool] $UseExistingRG) {
		$allVMData = ([AzureProvider]$this).DeployVMs($GlobalConfig, $SetupTypeData, $TestCaseData, $TestLocation, $RGIdentifier, $UseExistingRG)

	if ($($GlobalConfig.Global.OL.TestCredentials)) {
		$this.OLUserName = $($GlobalConfig.Global.OL.TestCredentials.OLUserName)
		$this.OLUserPassword = $($GlobalConfig.Global.OL.TestCredentials.OLUserPassword)
	} else {
		Write-LogErr "Cannnot find test credentials for OL platform"
		throw "OL credentials missing"
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