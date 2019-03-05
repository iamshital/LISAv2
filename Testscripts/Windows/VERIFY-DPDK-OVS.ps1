# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
param([object] $AllVmData,
		[object] $CurrentTestData)

function Get-TestStatus {
	param($testStatus)
	if ($testStatus -imatch "TestFailed") {
		Write-LogErr "Test failed. Last known status: $currentStatus."
		$testResult = "FAIL"
	}	elseif ($testStatus -imatch "TestAborted") {
		Write-LogErr "Test Aborted. Last known status : $currentStatus."
		$testResult = "ABORTED"
	}	elseif ($testStatus -imatch "TestCompleted") {
		Write-LogInfo "Test Completed."
		Write-LogInfo "DPDK build is Success"
		$testResult = "PASS"
	}	else {
		Write-LogErr "Test execution is not successful, check test logs in VM."
		$testResult = "ABORTED"
	}

	return $testResult
}


function Main {
	# Create test result
	$superUser = "root"
	$testResult = $null

	try {
		$noClient = $true
		$noServer = $true
		foreach ($vmData in $allVMData) {
			if ($vmData.RoleName -imatch "sender") {
				$clientVMData = $vmData
				$noClient = $false
			}
			elseif ($vmData.RoleName -imatch "receiver") {
				$noServer = $fase
				$serverVMData = $vmData
			}
		}
		if ($noClient) {
			Throw "No any master VM defined. Be sure that, Client VM role name matches with the pattern `"*master*`". Aborting Test."
		}
		if ($noServer) {
			Throw "No any slave VM defined. Be sure that, Server machine role names matches with pattern `"*slave*`" Aborting Test."
		}

		Write-LogInfo "CLIENT VM details :"
		Write-LogInfo "  RoleName : $($clientVMData.RoleName)"
		Write-LogInfo "  Public IP : $($clientVMData.PublicIP)"
		Write-LogInfo "  SSH Port : $($clientVMData.SSHPort)"
		Write-LogInfo "  Internal IP : $($clientVMData.InternalIP)"
		Write-LogInfo "SERVER VM details :"
		Write-LogInfo "  RoleName : $($serverVMData.RoleName)"
		Write-LogInfo "  Public IP : $($serverVMData.PublicIP)"
		Write-LogInfo "  SSH Port : $($serverVMData.SSHPort)"
		Write-LogInfo "  Internal IP : $($serverVMData.InternalIP)"

		# PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.
		Provision-VMsForLisa -allVMData $allVMData -installPackagesOnRoleNames "none"
		#endregion

		Write-LogInfo "Getting Active NIC Name."
		$getNicCmd = ". ./utils.sh &> /dev/null && get_active_nic_name"
		$clientNicName = (Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username $superUser -password $password -command $getNicCmd).Trim()
		$serverNicName = (Run-LinuxCmd -ip $clientVMData.PublicIP -port $serverVMData.SSHPort -username $superUser -password $password -command $getNicCmd).Trim()
		if ($serverNicName -eq $clientNicName) {
			Write-LogInfo "Client and Server VMs have same nic name: $clientNicName"
		} else {
			Throw "Server and client SRIOV NICs are not same."
		}
		if ($currentTestData.AdditionalHWConfig.Networking -imatch "SRIOV") {
			$DataPath = "SRIOV"
		} else {
			$DataPath = "Synthetic"
		}
		Write-LogInfo "CLIENT $DataPath NIC: $clientNicName"
		Write-LogInfo "SERVER $DataPath NIC: $serverNicName"

		Write-LogInfo "Generating constants.sh ..."
		$constantsFile = "$LogDir\constants.sh"
		Set-Content -Value "#Generated by Azure Automation." -Path $constantsFile
		Add-Content -Value "vms=$($serverVMData.RoleName),$($clientVMData.RoleName)" -Path $constantsFile
		Add-Content -Value "server=$($serverVMData.InternalIP)" -Path $constantsFile
		Add-Content -Value "client=$($clientVMData.InternalIP)" -Path $constantsFile
		Add-Content -Value "nicName=eth1" -Path $constantsFile

		foreach ($param in $currentTestData.TestParameters.param) {
			Add-Content -Value "$param" -Path $constantsFile
			if ($param -imatch "modes") {
				$modes = ($param.Replace("modes=",""))
			}
		}
		$detectedDistro = Detect-LinuxDistro -VIP $vmData.PublicIP -SSHport $vmData.SSHPort `
			-testVMUser $user -testVMPassword $password
		$currentKernelVersion = Run-LinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort `
			-username $user -password $password -command "uname -r"
		if (IsGreaterKernelVersion -actualKernelVersion $currentKernelVersion -detectedDistro $detectedDistro) {
			Write-LogInfo "Confirmed Kernel version supported: $currentKernelVersion"
		} else {
			$msg = "Unsupported Kernel version: $currentKernelVersion"
			Write-LogErr $msg
			throw $msg
		}

		Write-LogInfo "constants.sh created successfully..."
		Write-LogInfo "test modes : $modes"
		Write-LogInfo (Get-Content -Path $constantsFile)
		#endregion

		#region INSTALL CONFIGURE DPDK
		$install_configure_dpdk = @"
cd /root/
./dpdk_generic_setup.sh 2>&1 > dpdkConsoleLogs.txt
. utils.sh
collect_VM_properties
"@
		Set-Content "$LogDir\StartDpdkOvsSetup.sh" $install_configure_dpdk
		Copy-RemoteFiles -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-files "$constantsFile,$LogDir\StartDpdkOvsSetup.sh" -username $superUser -password $password -upload

		Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $superUser -password $password -command "chmod +x *.sh" | Out-Null
		$testJob = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $superUser -password $password -command "./StartDpdkOvsSetup.sh" -RunInBackground
		#endregion

		#region MONITOR INSTALL CONFIGURE DPDK
		while ((Get-Job -Id $testJob).State -eq "Running") {
			$currentStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
				-username $superUser -password $password -command "tail -2 dpdkConsoleLogs.txt | head -1"
			Write-LogInfo "Current Test Status : $currentStatus"
			Wait-Time -seconds 20
		}
		$dpdkStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $superUser -password $password -command "cat /root/state.txt"
		$testResult = Get-TestStatus $dpdkStatus
		if ($testResult -ne "PASS") {
			return $testResult
		}

		#region INSTALL CONFIGURE OVS
		$install_configure_ovs = @"
cd /root/
./ovs_setup.sh 2>&1 > ovsConsoleLogs.txt
. utils.sh
collect_VM_properties
"@
		Set-Content "$LogDir\StartOvsSetup.sh" $install_configure_ovs
		Copy-RemoteFiles -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-files "$LogDir\StartOvsSetup.sh" -username $superUser -password $password -upload

		Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $superUser -password $password -command "chmod +x *.sh" | Out-Null
		$testJob = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $superUser -password $password -command "./StartOvsSetup.sh" -RunInBackground
		#endregion

		#region MONITOR INSTALL CONFIGURE OVS
		while ((Get-Job -Id $testJob).State -eq "Running") {
			$currentStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
				-username $superUser -password $password -command "tail -2 ovsConsoleLogs.txt | head -1"
			Write-LogInfo "Current Test Status : $currentStatus"
			Wait-Time -seconds 20
		}
		$ovsStatus = Run-LinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort `
			-username $superUser -password $password -command "cat /root/state.txt"
		$testResult = Get-TestStatus $ovsStatus
		if ($testResult -ne "PASS") {
			return $testResult
		}
	} catch {
		$ErrorMessage =  $_.Exception.Message
		$ErrorLine = $_.InvocationInfo.ScriptLineNumber
		Write-LogErr "EXCEPTION : $ErrorMessage at line: $ErrorLine"
		$testResult = "FAIL"
	}
	return $testResult
}

Main
