# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
param([object] $AllVmData,
      [object] $CurrentTestData)

function Main {
    $currentTestResult = Create-TestResultObject
    try {
        $PreviousTestResult = "PASS"
        foreach ($param in $CurrentTestData.TestParameters.param) {
            if ($Param -imatch "LIS_TARBALL_URL_CURRENT") {
                $LISTarballUrlCurrent = "" #Extract from param
            }
            if ($Param -imatch "LIS_TARBALL_URL_OLD") {
                $LISTarballUrlOld = "" #Extract from param
            }
        }

        ### Functions ##############################
        # Note : These functions should only return boolean true / false
        Function Install-LIS ($LISTarballUrl) {

            #Check if it has LIS already installed.

            if ($LisDetected) {
                #execute ./upgrade.sh command
            } else {
                #execute ./install.sh command
            }

            #Verify Daemons

            #Reboot and verify
        }
        Function Upgrade-LIS ($LISTarballUrlOld, $LISTarballUrlCurrent, [switch]$RunBondBeforeUpgrade) {
            Install-LIS -LISTarballUrl $LISTarballUrlOld
            Install-LIS -LISTarballUrl $LISTarballUrlCurrent
        }
        Function Downgrade-LIS ($LISTarballUrlOld) {
            # Uninstall the Current LIS
            Install-LIS -LISTarballUrl $LISTarballUrlOld
        }
        Function Uninstall-LIS {
            # Uninstall

            # Reboot

            # Verify
        }
        Function Upgrade-Kernel ([switch]$MinorKernelOnly){
            #Upgrade kernel
            #Check if kernel is upgraded.
        }

        Function Run-BondingScript {
            #Download bondvf.sh
            #Run : chmod 775 bondvf.sh && ~/bondvf.sh

        }
        Function Check-BondingScriptErrors {
            # dmesg | grep -q 'bond0: Error'
            # grep -qi 'Call Trace' /var/log/messages
        }
        ###################################################

        ### Scenarios ###############################
        # Note : These functions should only return string PASS/FAIL/Aborted
        Function  LIS-Install-Scenario-1 ($PreviousTestResult) {
            #Scenario Information : Install the current LIS
            if ($PreviousTestResult -eq "PASS") {
                Install-LIS -LISTarballUrl $LISTarballUrlCurrent
                if ($TestPlatform -eq "HyperV") {
                    #Take Snapshot with name
                    Create-HyperVCheckpoint -VMData $AllVMData -CheckpointName "CURRENT_LIS_INSTALLED"
                }
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-2 ($PreviousTestResult) {
            #Scenario Information : Upgrade the current LIS
            if ($PreviousTestResult -eq "PASS") {
                Upgrade-LIS -LISTarballUrlOld $LISTarballUrlOld -LISTarballUrlCurrent $LISTarballUrlCurrent
                if ($TestPlatform -eq "HyperV") {
                    #Take Snapshot with name
                    Create-HyperVCheckpoint -VMData $AllVMData -CheckpointName "CURRENT_LIS_UPGRADED"
                }
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-3 ($PreviousTestResult) {
            #Scenario Information : Downgrade LIS to old LIS.
            if ($PreviousTestResult -eq "PASS") {
                if ($TestPlatform -eq "HyperV") {
                    Apply-HyperVCheckpoint -VMData $AllVMData -CheckpointName "CURRENT_LIS_UPGRADED"

                } elseif ($TestPlatform -eq "Azure") {
                    Upgrade-LIS -LISTarballUrlOld $LISTarballUrlOld -LISTarballUrlCurrent $LISTarballUrlCurrent
                }
                Downgrade-LIS -LISTarballUrlOld $LISTarballUrlOld
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-4 ($PreviousTestResult) {
            #Scenario Information : Upgrade kernel, install LIS.
            if ($PreviousTestResult -eq "PASS") {
                Upgrade-Kernel
                Install-LIS -LISTarballUrl $LISTarballUrlCurrent
                #Installation should fail. So invert the Install-LIS result.
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-5 ($PreviousTestResult) {
            #Scenario Information : Install LIS and upgrade kernel.
            if ($PreviousTestResult -eq "PASS") {
                if ($TestPlatform -eq "HyperV") {
                    Apply-HyperVCheckpoint -VMData $AllVMData -CheckpointName "CURRENT_LIS_INSTALLED"
                } elseif ($TestPlatform -eq "Azure") {
                    Install-LIS -LISTarballUrl $LISTarballUrlCurrent
                }
                Upgrade-Kernel
                #Verify if VM is booted with kernel drivers.
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-6 ($PreviousTestResult) {
            #Scenario Information : Upgrade LIS, upgrade kernel.
            if ($PreviousTestResult -eq "PASS") {
                if ($TestPlatform -eq "HyperV") {
                    Apply-HyperVCheckpoint -VMData $AllVMData -CheckpointName "CURRENT_LIS_UPGRADED"
                } elseif ($TestPlatform -eq "Azure") {
                    Upgrade-LIS -LISTarballUrlOld $LISTarballUrlOld -LISTarballUrlCurrent $LISTarballUrlCurrent
                }
                Upgrade-Kernel
                #Verify if VM is booted with kernel drivers.
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-7 ($PreviousTestResult) {
            # Scenario Information : Upgrade minor kernel, Upgrade LIS
            # If it's an Oracle distro, skip the test (Copied from LIS-Test HyperV)
            if ($PreviousTestResult -eq "PASS") {
                Upgrade-Kernel -MinorKernelOnly
                Upgrade-LIS -LISTarballUrlOld $LISTarballUrlOld -LISTarballUrlCurrent $LISTarballUrlCurrent
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-8 ($PreviousTestResult) {
            # Scenario Information : Uninstall LIS.
            if ($PreviousTestResult -eq "PASS") {
                if ($TestPlatform -eq "HyperV") {
                    Apply-HyperVCheckpoint -VMData $AllVMData -CheckpointName "CURRENT_LIS_INSTALLED"
                } elseif ($TestPlatform -eq "Azure") {
                    Install-LIS -LISTarballUrl $LISTarballUrlCurrent
                }
                Uninstall-LIS
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-9 ($PreviousTestResult) {
            # Scenario Information : Run bonding script and install LIS, Upgrade Kernel
            # This TC is only supported for 7.3 and 7.4 (Copied from LIS-Test HyperV)
            if ($PreviousTestResult -eq "PASS") {
                Run-BondingScript
                Install-LIS -LISTarballUrl $LISTarballUrlCurrent
                Check-BondingScriptErrors
                Upgrade-Kernel
                Check-BondingScriptErrors
            } else {
                return "Aborted"
            }
        }
        Function LIS-Install-Scenario-10 ($PreviousTestResult) {
            # Scenario Information : Run bonding script and Upgrade LIS, Upgrade Kernel
            # This TC is only supported for 7.3 and 7.4 (Copied from LIS-Test HyperV)
            if ($PreviousTestResult -eq "PASS") {
                Upgrade-LIS -LISTarballUrlOld $LISTarballUrlOld -LISTarballUrlCurrent $LISTarballUrlCurrent -RunBondBeforeUpgrade
                Check-BondingScriptErrors
                Upgrade-Kernel
                Check-BondingScriptErrors
            } else {
                return "Aborted"
            }
        }

        foreach ($Scenario in $CurrentTestData.TestParameters.param) {
            $PreviousTestResult = $testResult
            switch ($Scenario) {
                "LIS-Install-Scenario-1" {
                    $testResult = LIS-Install-Scenario-1 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-2" {
                    $testResult = LIS-Install-Scenario-2 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-3" {
                    $testResult = LIS-Install-Scenario-3 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-4" {
                    $testResult = LIS-Install-Scenario-4 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-5" {
                    $testResult = LIS-Install-Scenario-5 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-6" {
                    $testResult = LIS-Install-Scenario-6 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-7" {
                    $testResult = LIS-Install-Scenario-7 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-8" {
                    $testResult = LIS-Install-Scenario-8 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-9" {
                    $testResult = LIS-Install-Scenario-9 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                "LIS-Install-Scenario-10" {
                    $testResult = LIS-Install-Scenario-10 -PreviousTestResult $PreviousTestResult
                    $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "$Scenario" `
                    -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
                    break;
                }
                default {
                    #Do nothing.
                }
            }
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $ErrorLine = $_.InvocationInfo.ScriptLineNumber
        Write-LogInfo "EXCEPTION : $ErrorMessage at line: $ErrorLine"
    }
    finally {
        if (!$testResult) {
            $testResult = "Aborted"
            $CurrentTestResult.TestSummary += New-ResultSummary -testResult $testResult -metaData "LIS-INSTALL-SCENARIOS" `
                -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
        }
        $resultArr += $testResult
    }
    $currentTestResult.TestResult = Get-FinalResultHeader -resultarr $resultArr
    return $currentTestResult
}

Main
