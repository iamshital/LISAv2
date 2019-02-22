# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

param([String] $TestParams, [object] $AllVmData)

$logFile = "versions.log"

function Main() {
    $publicIP = $AllVMData.PublicIP
    $port = $AllVMData.SSHPort
    $currentTestResult = Create-TestResultObject
    $testResult = "PASS"

    $params = @{}
    $TestParams.Split(";") | ForEach-Object {
        $arg = $_.Split("=")[0]
        $val = $_.Split("=")[1]
        $params[$arg] = $val
    }

    $csvPath = $params["CSV_PATH"]

    Write-LogInfo "Using csv: $csvPath"
    if (-not (Test-Path $csvPath)) {
        Write-LogErr "Cannot find csv: $csvPath"
        throw "cannot find csv"
    }

    $csvContent = Import-Csv -Path $csvPath

    foreach ($package in $csvContent) {
        $packageName = $package.package
        $expectedVersion = $package.packagever

        $version = Run-LinuxCmd -username $user -password $password `
            -ip $publicIP -port $port -command "rpm -q $packageName || true" -runAsSudo
        if ($version -match "not installed") {
            $msg = "Cannot find version for package: $packageName"
            Write-LogWarn $msg
            echo $msg >> "${LogDir}\${logFile}"
            $testResult = "FAIL"
        } elseif (-not ($version | Select-String -SimpleMatch $expectedVersion)) {
            $msg = "Expected version: $expectedVersion does not match version: $version for package: $packageName"
            Write-LogWarn $msg
            echo $msg >> "${LogDir}\${logFile}"
            $testResult = "FAIL"
        } else {
            $msg = "Expected version: $expectedVersion matches version: $version for package: $packageName"
            Write-LogInfo $msg
            echo $msg >> "${LogDir}\${logFile}"
        }
    }

    $currentTestResult.TestResult = Get-FinalResultHeader -resultarr $testResult
    return $currentTestResult
}

Main