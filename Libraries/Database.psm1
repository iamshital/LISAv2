##############################################################################################
# Database.psm1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
	PS modules for LISAv2 test automation.
	Functions that handles database operation

.PARAMETER
	<Parameters>

.INPUTS


.NOTES
	Creation Date:
	Purpose/Change:

.EXAMPLE


#>
###############################################################################################

Function Get-SQLQueryOfTelemetryData ($TestPlatform,$TestLocation,$TestCategory,$TestArea,$TestName,$CurrentTestResult, `
									$ExecutionTag,$GuestDistro,$KernelVersion,$LISVersion,$HostVersion,$VMSize, `
									$Networking,$ARMImageName,$OsVHD,$LogFile,$BuildURL)
{
	try
	{
		$TestResult = $CurrentTestResult.TestResult
		$TestSummary = $CurrentTestResult.TestSummary
		$UTCTime = (Get-Date).ToUniversalTime()
		$DateTimeUTC = "$($UTCTime.Year)-$($UTCTime.Month)-$($UTCTime.Day) $($UTCTime.Hour):$($UTCTime.Minute):$($UTCTime.Second)"
		$testLogStorageAccount = $XmlSecrets.secrets.testLogsStorageAccount
		$testLogStorageAccountKey = $XmlSecrets.secrets.testLogsStorageAccountKey
		$testLogFolder = "$($UTCTime.Year)-$($UTCTime.Month)-$($UTCTime.Day)"
		$ticks= (Get-Date).Ticks
		$uploadFileName = Join-Path $env:TEMP "$TestName-$ticks.zip"
		$null = New-ZipFile -zipFileName $uploadFileName -sourceDir $LogDir
		$UploadedURL = .\Utilities\UploadFilesToStorageAccount.ps1 -filePaths $uploadFileName `
		-destinationStorageAccount $testLogStorageAccount -destinationContainer "lisav2logs" `
		-destinationFolder "$testLogFolder" -destinationStorageKey $testLogStorageAccountKey
		if ($BuildURL) {
			$BuildURL = "$BuildURL`consoleFull"
		} else {
			$BuildURL = ""
		}
		$dataTableName = "LISAv2Results"
		$SQLQuery = "INSERT INTO $dataTableName (DateTimeUTC,TestPlatform,TestLocation,TestCategory,TestArea,TestName,TestResult,SubTestName,SubTestResult,ExecutionTag,GuestDistro,KernelVersion,LISVersion,HostVersion,VMSize,Networking,ARMImage,OsVHD,LogFile,BuildURL) VALUES "
		$SQLQuery += "('$DateTimeUTC','$TestPlatform','$TestLocation','$TestCategory','$TestArea','$TestName','$testResult','','','$ExecutionTag','$GuestDistro','$KernelVersion','$LISVersion','$HostVersion','$VMSize','$Networking','$ARMImageName','$OsVHD','$UploadedURL', '$BuildURL'),"
		if ($TestSummary) {
			foreach ($tempResult in $TestSummary.Split('>')) {
				if ($tempResult) {
					$tempResult = $tempResult.Trim().Replace("<br /","").Trim()
					$subTestResult = $tempResult.Split(":")[$tempResult.Split(":").Count -1 ].Trim()
					$subTestName = $tempResult.Replace("$subTestResult","").Trim().TrimEnd(":").Trim()
					$SQLQuery += "('$DateTimeUTC','$TestPlatform','$TestLocation','$TestCategory','$TestArea','$TestName','$testResult','$subTestName','$subTestResult','$ExecutionTag','$GuestDistro','$KernelVersion','$LISVersion','$HostVersion','$VMSize','$Networking','$ARMImageName','$OsVHD','$UploadedURL', '$BuildURL'),"
				}
			}
		}
		$SQLQuery = $SQLQuery.TrimEnd(',')
		Write-LogInfo "Get the SQL query of test results:  done"
		return $SQLQuery
	}
	catch
	{
		Write-LogErr "Get the SQL query of test results:  ERROR"
		$line = $_.InvocationInfo.ScriptLineNumber
		$script_name = ($_.InvocationInfo.ScriptName).Replace($PWD,".")
		$ErrorMessage =  $_.Exception.Message
		Write-LogInfo "EXCEPTION : $ErrorMessage"
		Write-LogInfo "Source : Line $line in script $script_name."
	}
}

Function Upload-TestResultToDatabase {
	param (
		[Parameter(ParameterSetName="TestResult")]
		[Array] $TestResultData, [Object] $DatabaseConfig,
		[Parameter(ParameterSetName="TelemetryData")]
		[String]$SQLQuery
	)
	$server = $DatabaseConfig.server
	$dbUser = $DatabaseConfig.user
	$dbPassword = $DatabaseConfig.password
	$dbName = $DatabaseConfig.dbname
	$tableName = $DatabaseConfig.dbtable
	$DBDetailsAvailable = $server -and $dbUser -and $dbPassword -and $dbName
	$TestResultReadyToUpload = $DBDetailsAvailable -and $tableName
	if (($PSCmdlet.ParameterSetName -eq "TelemetryData") -and $DBDetailsAvailable) {
		Run-SQLQuery -DatabaseServer $server -DatabaseName $dbName -DatabaseUsername $dbUser `
		-DatabasePassword $dbPassword -SQLQuery $SQLQuery`
		Write-LogInfo "Uploading telemetry data to database :  Succeeded."
	} elseif (($PSCmdlet.ParameterSetName -eq "TestResult") -and $TestResultReadyToUpload) {
		foreach ($map in $TestResultData) {
			$queryKey = "INSERT INTO $tableName ("
			$queryValue = "VALUES ("
			foreach ($key in $map.Keys) {
				$queryKey += "$key,"
				if ($map[$key] -ne $null -and $map[$key].GetType().Name -eq "String") {
					$queryValue += "'$($map[$key])',"
				} else {
					$queryValue += "$($map[$key]),"
				}
			}
			$query = $queryKey.TrimEnd(",") + ") " + $queryValue.TrimEnd(",") + ")"
			Run-SQLQuery -DatabaseServer $server -DatabaseName $dbName -DatabaseUsername $dbUser `
				-DatabasePassword $dbPassword -SQLQuery $query`
		}
		Write-LogInfo "Uploading test result to database :  Succeeded."
	} else {
		Write-LogErr "Database details are not provided. Results will not be uploaded to database."
	}
}

Function Run-SQLQuery {
	param (
		[string] $DatabaseServer,
		[string] $DatabaseName,
		[string] $DatabaseUsername,
		[string] $DatabasePassword,
		[string] $SQLQuery
	)
	try {
		Write-LogInfo "SQL Query: $SQLQuery"
		$connectionString = "Server=$DatabaseServer;uid=$DatabaseUsername; pwd=$DatabasePassword;Database=$DatabaseName;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
		$connection = New-Object System.Data.SqlClient.SqlConnection
		$connection.ConnectionString = $connectionString
		$connection.Open()
		$command = $connection.CreateCommand()
		$command.CommandText = $SQLQuery
		$null = $command.executenonquery()
		$connection.Close()
		Write-LogInfo "SQL Query: Succeeded."
	} catch {
		Write-LogErr "SQL Query: Failed."
		$line = $_.InvocationInfo.ScriptLineNumber
		$script_name = ($_.InvocationInfo.ScriptName).Replace($PWD,".")
		$ErrorMessage =  $_.Exception.Message
		Write-LogInfo "EXCEPTION : $ErrorMessage"
		Write-LogInfo "Source : Line $line in script $script_name."
	}
}
Function Get-VMProperties ($PropertyFilePath) {
	if (Test-Path $PropertyFilePath) {
		$GuestDistro = Get-Content $PropertyFilePath | Select-String "OS type"| ForEach-Object {$_ -replace ",OS type,",""}
		$HostOS = Get-Content $PropertyFilePath | Select-String "Host Version"| ForEach-Object {$_ -replace ",Host Version,",""}
		$KernelVersion = Get-Content $PropertyFilePath | Select-String "Kernel version"| ForEach-Object {$_ -replace ",Kernel version,",""}

		$objNode = New-Object -TypeName PSObject
		Add-Member -InputObject $objNode -MemberType NoteProperty -Name GuestDistro -Value $GuestDistro -Force
		Add-Member -InputObject $objNode -MemberType NoteProperty -Name HostOS -Value $HostOS -Force
		Add-Member -InputObject $objNode -MemberType NoteProperty -Name KernelVersion -Value $KernelVersion -Force
		return $objNode
	} else {
		Write-LogErr "The property file doesn't exist: $PropertyFilePath"
		return $null
	}
}

