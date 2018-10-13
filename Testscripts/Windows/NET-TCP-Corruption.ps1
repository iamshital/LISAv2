# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Synopsis
    Run NET_Corruption in the guest VM in order to install netcat
    and set the desired corruption. Start netcat listen process on
    the VM and the receive process on windows host. Check for call traces.
    Compare file hashes.
#>

param ([String] $TestParams)

function Main {
    param (
        $VMName,
        $HvServer,
        $IPv4,
        $VMPort,
        $VMPassword,
        $VMUserName
    )
    $port = 1234
    $sourceFilePath = "/tmp/testfile"
    $destionationFilePath = ".\testfile"
    $netcatScriptPath = "listen.sh"
    $netcatBinPath = ".\Tools\nc.exe"

    # nc.exe should be in Tools
    if (-not (Test-Path $netcatBinPath)) {
        LogErr "Unable to find netcat binary"
        return "FAIL"
    }

    # Copy dependency files to VM
    RemoteCopy -upload -uploadTo $IPv4 -Port $VMPort `
        -files ".\Testscripts\Linux\utils.sh,.\Testscripts\Linux\NET-Corruption.sh" `
        -Username "root" -password $VMPassword

    # Run NET-Corruption.sh on the VM
    LogMsg "Info: Configuring VM"
    $cmdToSend = "cp /home/${VMUserName}/constants.sh . ; bash NET-Corruption.sh ${sourceFilePath} ${port} ${netcatScriptPath} 2>/dev/null"
    $retVal = RunLinuxCmd -username "root" -password $VMPassword -ip $IPv4 -port $VMPort `
        -command $cmdToSend -ignoreLinuxExitCode:$true
    $state = RunLinuxCmd -username "root" -password $VMPassword -ip $IPv4 -port $VMPort `
        -command "cat state.txt" -ignoreLinuxExitCode:$true
    if ($state -notMatch "Completed") {
        LogErr "NET-TCP-Corruption.sh failed on guest"
        return "FAIL"
    }

    LogMsg "Info: Checking system logs path"
    $sts = RunLinuxCmd -username "root" -password $VMPassword -ip $IPv4 -port $VMPort `
        -command "[[ -f /var/log/syslog ]];echo `$?" -ignoreLinuxExitCode:$true
    if ($sts -eq "1") {
        $logPath = '/var/log/messages'
    } else {
        $logPath = '/var/log/syslog'
    }

    # Start netcat on guest
    Start-Sleep 5
    LogMsg "Info: Starting netcat server on VM Job"
    $cmd = "setsid ./listen.sh 2>&1"
    RunLinuxCmd -username "root" -password $VMPassword -ip $IPv4 -port $VMPort `
        -command $cmd -ignoreLinuxExitCode:$true -RunInBackGround

    $jobName = "ReceiveJobNC"
    $ipAddr = (Get-VMNetworkAdapter -VMName ${VMName} -ComputerName $HvServer)[1].IPAddresses[0]
    $cmd = "cmd.exe /C " + "'" + "${netcatBinPath} -v -w 2 ${ipAddr} ${port} > ${destionationFilePath}" + "'"
    LogMSg "Info: Running command ${cmd} on host"
    $cmd | Out-File ./nccmd.ps1
    $sts = ./nccmd.ps1
    Start-Job -Name ${jobName} -ScriptBlock {./nccmd.ps1}


    LogMsg "Info: Checking for call traces in ${logPath}"
    $grepCmd = "grep -i 'Call Trace' ${logPath}"
    while ((Get-Job -Name ${jobName}).State -eq "Running") {
        $retVal = RunLinuxCmd -username "root" -password $VMPassword -ip $IPv4 -port $VMPort `
            -command $grepCmd -ignoreLinuxExitCode:$true
        if ($retVal) {
            LogErr "Call traces found in ${logPath}"
            return "FAIL"
        }
        Start-Sleep -s 5
    }

    LogMsg "Info: Comparing hashes"
    $localHash = (Get-FileHash -Algorithm MD5 $destionationFilePath).Hash
    $remoteHash = RunLinuxCmd -username "root" -password $VMPassword -ip $IPv4 -port $VMPort `
        -command "md5sum ${sourceFilePath}" -ignoreLinuxExitCode:$true
    $remoteHash = $remoteHash.Split(" ")[0]
    if (-not $remoteHash) {
        LogErr "Unable to get file hash from VM"
        return "FAIL"
    }

    LogMsg "File hashes: ${remoteHash} - ${localHash}"
    if ($remoteHash.ToUpper() -ne $localHash) {
        LogErr "File hashes do not match."
        return "FAIL"
    }
    Stop-Job -Name $jobName -ErrorAction SilentlyContinue
    Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
    LogMsg "Test completed successfully"
    return "PASS"
}

Main -VMName $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
    -IPv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort -VMPassword $password `
    -VMUserName $user