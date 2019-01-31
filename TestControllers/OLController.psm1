##############################################################################################
# OLController.psm1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
	PS modules for LISAv2 test automation
	This module drives the test on Azure

.PARAMETER
	<Parameters>

.INPUTS


.NOTES
	Creation Date:
	Purpose/Change:

.EXAMPLE


#>
###############################################################################################
using Module ".\AzureController.psm1"
using Module "..\TestProviders\OLProvider.psm1"

Class OLController : AzureController
{
	[string] $OLUserName
    [string] $OLUserPassword
    [string] $OLImageUrl 
    [string] $OLImageName
    [string] $HostFwdPort

	OLController() {
		$this.TestProvider = New-Object -TypeName "OLProvider"
		$this.TestPlatform = "OL"	
	}

	[void] ParseAndValidateParameters([Hashtable]$ParamTable) {
		([AzureController]$this).ParseAndValidateParameters([Hashtable]$ParamTable)
    }

    [void] PrepareTestEnvironment($XMLSecretFile) {
		([AzureController]$this).PrepareTestEnvironment($XMLSecretFile)
		$OLConfig = $this.GlobalConfig.Global.OL
		if ($this.XMLSecrets) {
			$secrets = $this.XMLSecrets.secrets
			$OLConfig.TestCredentials.OLUserName = $secrets.OLUserName
            $OLConfig.TestCredentials.OLUserPassword = $secrets.OLUserPassword
            $OLConfig.TestCredentials.OLImageUrl = $secrets.OLImageUrl
            $OLConfig.TestCredentials.OLImageName = $secrets.OLImageName			
		}
		$this.OLUserName = $OLConfig.TestCredentials.OLUserName
        $this.OLUserPassword = $OLConfig.TestCredentials.OLUserPassword
        $this.OLImageUrl = $OLConfig.TestCredentials.OLImageUrl
		$this.OLImageName = $OLConfig.TestCredentials.OLImageName
		$this.HostFwdPort = $OLConfig.TestCredentials.HostFwdPort

		$this.GlobalConfig.Save($this.GlobalConfigurationFilePath )

		Write-LogInfo "Setting global variables"
		$this.SetGlobalVariables()
		Write-Host "controller : -Username $($this.OLUserName) -password $($this.OLUserPassword) -imageurl $($this.OLImageUrl) imagename $($this.OLImageName)"	
	}

	[void] SetGlobalVariables() {
		([AzureController]$this).SetGlobalVariables()
	}
}