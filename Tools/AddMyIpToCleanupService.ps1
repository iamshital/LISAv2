
param (
    $ResourceGroup
)

while ($NSGid -inotmatch "networkSecurityGroups"){
    $RGNAME = $ResourceGroup
    Write-Host "Get-AzureRmResource -ResourceType `"Microsoft.Network/virtualNetworks`" -ResourceGroupName  $RGName -ExpandProperties"
    $VNET = Get-AzureRmResource -ResourceType "Microsoft.Network/virtualNetworks" -ResourceGroupName  $RGName -ExpandProperties
    $NSGid = $VNET.Properties.subnets[0].properties.networkSecurityGroup.Id
    Start-Sleep -Seconds 5 -Verbose
}
Write-Host "Collected Network Security Group : $NSGid"
Write-Host "Get-AzureRmResource -ResourceID $NSGid"
$NSGresource = Get-AzureRmResource -ResourceID $NSGid
$NSGNAME = $NSGresource.Name
$NSGRGNAME = $NSGresource.ResourceGroupName
Write-Host "Get-AzureRmNetworkSecurityGroup -Name $NSGNAME -ResourceGroupName $NSGRGNAME"
$NSGproperties = Get-AzureRmNetworkSecurityGroup -Name $NSGNAME -ResourceGroupName $NSGRGNAME
$CurrentIP = [string](Invoke-RestMethod http://ipinfo.io/json | Select -exp ip)
Write-Host "Collected current public IP : $CurrentIP"
$i=0;foreach ( $rule in $NSGproperties.SecurityRules) { 
    if ($rule.name -eq "Cleanuptool-Allow-100"){ 
        Write-Host "$($rule.name) found at location $($i+1)"; 
        break;
    };
    $i+=1 
}
if ( -not $NSGproperties.SecurityRules[$i].SourceAddressPrefix.Contains("$CurrentIP") ) {
    [void] ($NSGproperties.SecurityRules[$i].SourceAddressPrefix.Add("$CurrentIP"))
    [void] (Get-AzureRmResourceLock | Where { $_.ResourceName -eq $NSGNAME -and $_.ResourceGroupName -eq  $NSGRGNAME  } | Remove-AzureRmResourceLock -Verbose -Force)
    Write-Host "Updadting security group..."
    [void] ($NSGproperties | Set-AzureRmNetworkSecurityGroup -Verbose)
    [void] (Set-AzureRmResourceLock -LockName "ReadOnly" -LockLevel ReadOnly -LockNotes "Added by LISAv2" -Force -Verbose -ResourceName $NSGNAME -ResourceGroupName $NSGRGNAME -ResourceType 'Microsoft.Network/networkSecurityGroups')
    Write-Host "Updadting security group Done!"
}
else {
    Write-Host "Updadting security group not required."
}
