[CmdletBinding()]
param(
    [parameter(Mandatory = $true)]
    [String] $JobId,
    [parameter(Mandatory = $true)]
    [String] $DistroVersion,
    [parameter(Mandatory = $true)]
    [String] $TestCategory,
    [String] $TestArea,
    [String] $TestNames,
    [string] $TestTag,
    [string] $TestPriority,
    [String] $LISAImagesShareUrl,
    [String] $LisUrl,
    [String] $LisOldUrl,
    [String] $Delay
)

foreach ($key in $MyInvocation.BoundParameters.keys) {
    $value = (get-variable $key).Value 
    write-host "$key -> $value"
}

function Main {
    if (!$TestCategory) { $TestCategory = "All" }
    if (!$TestArea)     { $TestArea = "All" }
    if (!$TestNames)    { $TestNames = "All" }
    if (!$TestTag)      { $TestTag = "All" }
    if (!$TestPriority) { $TestPriority = "All" }
    git checkout downloadfile
    Write-Output "Sleeping $Delay seconds..."
    Start-Sleep $Delay
    
    Write-Host "Getting the proper VHD folder name for LISA with $DistroVersion"
    $imageFolder = Join-Path $LISAImagesShareUrl $DistroVersion.split("_")[0]
    $imageFolder = Join-Path $imageFolder $DistroVersion
    $parentVhd = $(Get-ChildItem $imageFolder | Where-Object { $_.Extension -eq ".vhd" -or $_.Extension -eq ".vhdx"} | Sort LastWriteTime | Select -Last 1).Name
    $VHD_Path = Join-Path $imageFolder $parentVhd
    #$VHDName = $VHD_Path | Split-Path -Leaf
    #$VHD_Path = "https://shitalfileshare.blob.core.windows.net/vhds/$($VHDName)"
    $VMgeneration = "1"
    if ($DistroVersion -like "*gen2vm*") {
        $VMgeneration = "2"
    }
    Write-Output "Starting LISAv2"
    try {
        $SourceVHDPath = $VHD_Path | Split-Path -Parent
        $OsVHD = $VHD_Path | Split-Path -Leaf        
        if ((Test-Path $VHD_Path) -or ($VHD_Path.StartsWith("http"))) {
            Write-Host "ComputerName: $env:computername"
            Write-Host "VHD : $VHD_Path"
            #$VHD_Path = "\\redmond\wsscfs\OSTC\LIS\VHD\Cloudbase\CentOS\CentOS_7.2_x64\CentOS72x64.vhdx"
            $command = ".\Run-LisaV2.ps1 -TestPlatform HyperV"
            $command += " -XMLSecretFile '$env:Azure_Secrets_File'"
            $command += " -TestLocation 'localhost'"
            $command += " -RGIdentifier '$JobId'"
            $command += " -OsVHD '$VHD_Path'"
            $command += " -TestCategory '$TestCategory'"
            $command += " -TestArea '$TestArea'"
            $command += " -VMGeneration '$VMgeneration'"
            $command += " -ForceDeleteResources"
            $command += " -ExitWithZero"
            if ($TestNames) {
                $command += " -TestNames '$TestNames'"
            }
            if ($TestArea -imatch "LIS_DEPLOY") {
                $command += " -CustomParameters 'LIS_OLD_URL=$LisOldUrl;LIS_CURRENT_URL=$LisUrl'"
            } else {
                $command += " -CustomLIS '$LisUrl'"
            }
            Write-Output $PsCmd
            powershell.exe -NonInteractive -ExecutionPolicy Bypass `
                -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$command;EXIT $global:LastExitCode"
        }
        else {
            Write-Output "Unable to locate VHD : $VHD_Path."
        }
    }
    catch {
        $ErrorMessage =  $_.Exception.Message
		Write-Output "EXCEPTION : $ErrorMessage"
    }
}

Main
