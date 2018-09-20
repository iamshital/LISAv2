##############################################################################################
# UpdateGlobalConfigurationFromXmlSecrets.ps1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
    Update GlobalConfigurations.xml

.PARAMETER
    <Parameters>

.INPUTS


.NOTES
    Creation Date:
    Purpose/Change:

.EXAMPLE


#>
###############################################################################################

param(
    [parameter(Mandatory=$true)]
    [string]$XmlSecretsFilePath
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootPath = Split-Path -Parent $scriptPath
Get-ChildItem (Join-Path $rootPath "Libraries") -Recurse | `
    Where-Object { $_.FullName.EndsWith(".psm1") } | `
    ForEach-Object { Import-Module $_.FullName -Force -Global }

$xmlGlobalConfigPath = Resolve-Path -Path ".\XML\GlobalConfigurations.xml"
$XmlSecrets = [xml](Get-Content $XmlSecretsFilePath)
$GlobalConfigurationXMLFilePath = Resolve-Path ".\XML\GlobalConfigurations.xml"
$GlobalXML = [xml](Get-Content $GlobalConfigurationXMLFilePath  )
$GlobalXML.Global.Azure.Subscription.SubscriptionID = $XmlSecrets.secrets.SubscriptionID

$GlobalXML.Global.Azure.TestCredentials.LinuxUsername = $XmlSecrets.secrets.linuxTestUsername
$GlobalXML.Global.Azure.TestCredentials.LinuxPassword = $XmlSecrets.secrets.linuxTestPassword
$GlobalXML.Global.Azure.ResultsDatabase.server = $XmlSecrets.secrets.DatabaseServer
$GlobalXML.Global.Azure.ResultsDatabase.user = $XmlSecrets.secrets.DatabaseUser
$GlobalXML.Global.Azure.ResultsDatabase.password = $XmlSecrets.secrets.DatabasePassword
$GlobalXML.Global.Azure.ResultsDatabase.dbname = $XmlSecrets.secrets.DatabaseName

$GlobalXML.Global.HyperV.TestCredentials.LinuxUsername = $XmlSecrets.secrets.linuxTestUsername
$GlobalXML.Global.HyperV.TestCredentials.LinuxPassword = $XmlSecrets.secrets.linuxTestPassword
$GlobalXML.Global.HyperV.ResultsDatabase.server = $XmlSecrets.secrets.DatabaseServer
$GlobalXML.Global.HyperV.ResultsDatabase.user = $XmlSecrets.secrets.DatabaseUser
$GlobalXML.Global.HyperV.ResultsDatabase.password = $XmlSecrets.secrets.DatabasePassword
$GlobalXML.Global.HyperV.ResultsDatabase.dbname = $XmlSecrets.secrets.DatabaseName

$GlobalXML.Save($GlobalConfigurationXMLFilePath )

LogMsg "Updated GlobalConfigurations.xml"