# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
<#
.Synopsis
    Verify the kernel config file.

.Description
    This script will checks the kernel config file for given image and
    compare it with master config file.

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.
#>
param([string] $testParams, [object] $AllVmData)

#######################################################################
#
# Main script body
#
#######################################################################
function Main {
    param (
        $TestParams, $allVMData
    )
    $currentTestResult = Create-TestResultObject
    try{
        $testResult = $null
        $masterurl = $TestParams.MasterConfigUrl
        $captureVMData = $allVMData
        $hvServer= $captureVMData.HyperVhost
        $Ipv4 = $captureVMData.PublicIP
        $VMPort= $captureVMData.SSHPort

        # Change the working directory
        Set-Location $WorkingDirectory

	# Download the master config file
        $masterconfigPath =  $WorkingDirectory + ".\" + "master.config"
        Write-LogInfo "masterurl $masterurl config path: $masterconfigPath"

        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile("$masterurl", "$masterconfigPath")

        try {
            Get-RemoteFileInfo -filename $masterconfigPath  -server $HvServer
        }
        catch {
            Write-LogErr "The .config file $masterconfigPath could not be found!"
            throw
        }

        Write-LogInfo "Copy the config files to Remote VM"
	# remote copy the config files to remote Virtual machine
        Copy-RemoteFiles -uploadTo $Ipv4 -port $VMPort -files $masterconfigPath -username $user -password $password -upload

	Write-LogInfo "Invoke-Remote script for kernel config validation"

        # Invoke the config verification remote script
        $remoteScript="kernel_config_verify_test.sh"
        $retval = Invoke-RemoteScriptAndCheckStateFile $remoteScript $user $password $Ipv4 $VMPort
        if ($retval -eq $False) {
            $testResult = "FAIL"
            throw "Running $remoteScript script failed on VM!"
        }
        Write-LogInfo "$remoteScript ran successfully"
        $testResult = "PASS"
    } catch {
        $ErrorMessage =  $_.Exception.Message
        $ErrorLine = $_.InvocationInfo.ScriptLineNumber
        Write-LogErr "EXCEPTION : $ErrorMessage at line: $ErrorLine"
    } finally {
        if (!$testResult) {
            $testResult = $resultAborted
        }
        $resultArr += $testResult
    }
    $currentTestResult.TestResult = Get-FinalResultHeader -resultarr $resultArr
    return $currentTestResult.TestResult
}

Main -TestParams  (ConvertFrom-StringData $TestParams.Replace(";","`n")) -allVMData $AllVmData
