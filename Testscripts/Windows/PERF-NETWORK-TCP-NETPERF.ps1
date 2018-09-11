# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

function Main {
    # Create test result 
    $resultArr = @()

    try {
        $noClient = $true
        $noServer = $true
        foreach ($vmData in $allVMData) {
            if ($vmData.RoleName -imatch "client") {
                $clientVMData = $vmData
                $noClient = $false
            }
            elseif ($vmData.RoleName -imatch "server") {
                $noServer = $fase
                $serverVMData = $vmData
            }
        }
        if ($noClient) {
            Throw "No any master VM defined. Be sure that, Client VM role name matches with the pattern `"*master*`". Aborting Test."
        }
        if ( $noServer ) {
            Throw "No any slave VM defined. Be sure that, Server machine role names matches with pattern `"*slave*`" Aborting Test."
        }
        #region CONFIGURE VM FOR TERASORT TEST
        LogMsg "CLIENT VM details :"
        LogMsg "  RoleName : $($clientVMData.RoleName)"
        LogMsg "  Public IP : $($clientVMData.PublicIP)"
        LogMsg "  SSH Port : $($clientVMData.SSHPort)"
        LogMsg "SERVER VM details :"
        LogMsg "  RoleName : $($serverVMData.RoleName)"
        LogMsg "  Public IP : $($serverVMData.PublicIP)"
        LogMsg "  SSH Port : $($serverVMData.SSHPort)"

        # PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.  
        ProvisionVMsForLisa -allVMData $allVMData -installPackagesOnRoleNames "none"
        #endregion

        LogMsg "Getting Active NIC Name."
        $getNicCmd = ". ./utils.sh &> /dev/null && get_active_nic_name"
        $clientNicName = (RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command $getNicCmd).Trim()
        $serverNicName = (RunLinuxCmd -ip $clientVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command $getNicCmd).Trim()
        if ( $serverNicName -eq $clientNicName) {
            $nicName = $clientNicName
        }
        else {
            Throw "Server and client SRIOV NICs are not same."
        }
        if ($EnableAcceleratedNetworking -or ($currentTestData.AdditionalHWConfig.Networking -imatch "SRIOV")) {
            $DataPath = "SRIOV"
        }
        else {
            $DataPath = "Synthetic"
        }
        LogMsg "CLIENT $DataPath NIC: $clientNicName"
        LogMsg "SERVER $DataPath NIC: $serverNicName"

        LogMsg "Generating constansts.sh ..."
        $constantsFile = "$LogDir\constants.sh"
        Set-Content -Value "#Generated by LISAv2." -Path $constantsFile
        Add-Content -Value "server=$($serverVMData.InternalIP)" -Path $constantsFile    
        Add-Content -Value "client=$($clientVMData.InternalIP)" -Path $constantsFile
        Add-Content -Value "nicName=$nicName" -Path $constantsFile
        foreach ($param in $currentTestData.TestParameters.param) {
            Add-Content -Value "$param" -Path $constantsFile
            if ( $param -imatch "test_type") {
                $TestType = $param.Split("=")[1]
            }
        }
        $TestType = $TestType.Replace('"','')
        LogMsg "constanst.sh created successfully..."
        LogMsg (Get-Content -Path $constantsFile)
        #endregion

        #region EXECUTE TEST
        $myString = @"
cd /root/
./perf_netperf.sh &> netperfConsoleLogs.txt
. utils.sh
collect_VM_properties
"@
        Set-Content "$LogDir\StartnetperfTest.sh" $myString
        RemoteCopy -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort -files ".\$constantsFile,.\$LogDir\StartnetperfTest.sh" -username "root" -password $password -upload
        RemoteCopy -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort -files $currentTestData.files -username "root" -password $password -upload

        $out = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "chmod +x *.sh"
        $testJob = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "/root/StartnetperfTest.sh" -RunInBackground
        #endregion

        #region MONITOR TEST
        while ((Get-Job -Id $testJob).State -eq "Running") {
            $currentStatus = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "tail -1 netperfConsoleLogs.txt | head -1"
            LogMsg "Current Test Staus : $currentStatus"
            WaitFor -seconds 20
        }
        $finalStatus = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "cat /root/state.txt"
        RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "netperfConsoleLogs.txt"
        RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "TestExecution.log"
        RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "netperf-client-sar-output.txt"
        RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "netperf-client-output.txt"
        RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "netperf-server-sar-output.txt"
        RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "netperf-server-output.txt"
        RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "VM_properties.csv"
        
        $testSummary = $null
        $NetperfReportLog = Get-Content -Path "$LogDir\netperf-client-sar-output.txt"
        
        #Region : parse the logs
        try {
            $RxPpsArray = @()
            $TxPpsArray = @()
            $TxRxTotalPpsArray = @()
            
            foreach ($line in $NetperfReportLog) {
                if ($line -imatch "$nicName" -and $line -inotmatch "Average") {
                    LogMsg "Collecting data from '$line'"
                    $line = $line.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                    for ($i = 0; $i -lt $line.split(' ').Count; $i++) { 
                        if ($line.split(" ")[$i] -eq "$nicName") { 
                            break; 
                        } 
                    }
                    $RxPps = [int]$line.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Split(" ")[$i+1]
                    $RxPpsArray += $RxPps
                    $TxPps = [int]$line.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Split(" ")[$i+2]
                    $TxPpsArray += $TxPps
                    $TxRxTotalPpsArray += ($RxPps + $TxPps)
                }
            }
            $RxData = $RxPpsArray | Measure-Object -Maximum -Minimum -Average
            $RxPpsMinimum = $RxData.Minimum
            $RxPpsMaximum = $RxData.Maximum
            $RxPpsAverage = [math]::Round($RxData.Average,0)
            LogMsg "RxPpsMinimum = $RxPpsMinimum"
            LogMsg "RxPpsMaximum = $RxPpsMaximum"
            LogMsg "RxPpsAverage = $RxPpsAverage"

            $TxData = $TxPpsArray | Measure-Object -Maximum -Minimum -Average
            $TxPpsMinimum = $TxData.Minimum
            $TxPpsMaximum = $TxData.Maximum
            $TxPpsAverage = [math]::Round($TxData.Average,0)
            LogMsg "TxPpsMinimum = $TxPpsMinimum"
            LogMsg "TxPpsMaximum = $TxPpsMaximum"
            LogMsg "TxPpsAverage = $TxPpsAverage"

            $RxTxTotalData = $TxRxTotalPpsArray | Measure-Object -Maximum -Minimum -Average
            $RxTxPpsMinimum = $RxTxTotalData.Minimum
            $RxTxPpsMaximum = $RxTxTotalData.Maximum
            $RxTxPpsAverage = [math]::Round($RxTxTotalData.Average,0)
            LogMsg "RxTxPpsMinimum = $RxTxPpsMinimum"
            LogMsg "RxTxPpsMaximum = $RxTxPpsMaximum"
            LogMsg "RxTxPpsAverage = $RxTxPpsAverage"

            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$RxPpsAverage" -metaData "Rx Average PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$RxPpsMinimum" -metaData "Rx Minimum PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$RxPpsMaximum" -metaData "Rx Maximum PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName

            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$TxPpsAverage" -metaData "Tx Average PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$TxPpsMinimum" -metaData "Tx Minimum PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$TxPpsMaximum" -metaData "Tx Maximum PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName

            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$RxTxPpsAverage" -metaData "RxTx Average PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$RxTxPpsMinimum" -metaData "RxTx Minimum PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
            $CurrentTestResult.TestSummary += CreateResultSummary -testResult "$RxTxPpsMaximum" -metaData "RxTx Maximum PPS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $ErrorLine = $_.InvocationInfo.ScriptLineNumber
            LogErr "EXCEPTION in Netperf log parsing : $ErrorMessage at line: $ErrorLine"            
        }
        #endregion

        #region Upload results to Netperf DB.
        try {
            LogMsg "Uploading the test results.."
            $dataSource = $xmlConfig.config.$TestPlatform.database.server
            $user = $xmlConfig.config.$TestPlatform.database.user
            $password = $xmlConfig.config.$TestPlatform.database.password
            $database = $xmlConfig.config.$TestPlatform.database.dbname
            $dataTableName = $xmlConfig.config.$TestPlatform.database.dbtable
            $TestExecutionTag = $xmlConfig.config.$TestPlatform.database.testTag
            if ($dataSource -And $user -And $password -And $database -And $dataTableName) {
                $GuestDistro    = cat "$LogDir\VM_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
                $HostType   = "$TestPlatform"
                $HostBy = ($xmlConfig.config.$TestPlatform.General.Location).Replace('"','')
                $HostOS = cat "$LogDir\VM_properties.csv" | Select-String "Host Version"| %{$_ -replace ",Host Version,",""}
                $GuestOSType    = "Linux"
                $GuestDistro    = cat "$LogDir\VM_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
                $GuestSize = $clientVMData.InstanceSize
                $KernelVersion  = cat "$LogDir\VM_properties.csv" | Select-String "Kernel version"| %{$_ -replace ",Kernel version,",""}
                $IPVersion = "IPv4"
                $ProtocolType = "TCP"
                $connectionString = "Server=$dataSource;uid=$user; pwd=$password;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
                $SQLQuery = "INSERT INTO $dataTableName (TestExecutionTag,TestDate,HostType,HostBy,HostOS,GuestOSType,GuestDistro,GuestSize,KernelVersion,IPVersion,ProtocolType,DataPath,TestType,RxPpsMinimum,RxPpsAverage,RxPpsMaximum,TxPpsMinimum,TxPpsAverage,TxPpsMaximum,RxTxPpsMinimum,RxTxPpsAverage,RxTxPpsMaximum) VALUES "
                $SQLQuery += "('$TestExecutionTag','$(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')','$HostType','$HostBy','$HostOS','$GuestOSType','$GuestDistro','$GuestSize','$KernelVersion','$IPVersion','$ProtocolType','$DataPath','$TestType','$RxPpsMinimum','$RxPpsAverage','$RxPpsMaximum','$TxPpsMinimum','$TxPpsAverage','$TxPpsMaximum','$RxTxPpsMinimum','$RxTxPpsAverage','$RxTxPpsMaximum')"
                LogMsg $SQLQuery
                $connection = New-Object System.Data.SqlClient.SqlConnection
                $connection.ConnectionString = $connectionString
                $connection.Open()
                $command = $connection.CreateCommand()
                $command.CommandText = $SQLQuery
                $result = $command.executenonquery()
                $connection.Close()
                LogMsg "Uploading the test results done!!"
            } else {
                LogErr "Invalid database details. Failed to upload result to database!"
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $ErrorLine = $_.InvocationInfo.ScriptLineNumber
            LogErr "EXCEPTION in uploading netperf results to DB : $ErrorMessage at line: $ErrorLine"                   
        }
        #endregion

        if ($finalStatus -imatch "TestFailed") {
            LogErr "Test failed. Last known status : $currentStatus."
            $testResult = "FAIL"
        }
        elseif ($finalStatus -imatch "TestAborted") {
            LogErr "Test Aborted. Last known status : $currentStatus."
            $testResult = "ABORTED"
        }
        elseif ($finalStatus -imatch "TestCompleted") {
            LogMsg "Test Completed."
            $testResult = "PASS"
        }
        LogMsg "Test result : $testResult"
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $ErrorLine = $_.InvocationInfo.ScriptLineNumber
        LogErr "EXCEPTION : $ErrorMessage at line: $ErrorLine"
    }
    finally {
        $metaData = "Netperf result"
        if (!$testResult) {
            $testResult = "ABORTED"
        }
        $resultArr += $testResult
    }

    $currentTestResult.TestResult = GetFinalResultHeader -resultarr $resultArr
    return $currentTestResult.TestResult  
}

Main
