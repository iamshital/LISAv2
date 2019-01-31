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
    $VHDName = $VHD_Path | Split-Path -Leaf
    $VHD_Path = "https://shitalfileshare.blob.core.windows.net/vhds/$($VHDName)"
    $VMgeneration = "1"
    if ($DistroVersion -like "*gen2vm*") {
        $VMgeneration = "2"
    }
    Write-Host "Starting LISAv2"
    try {
        dism /online /enable-feature /featurename:bits
        Start-Service -Name BITS -Verbose
        whoami.exe
        Get-Service -Name SENS
        Start-Service -Name SENS -Verbose
        $SourceVHDPath = $VHD_Path | Split-Path -Parent
        $OsVHD = $VHD_Path | Split-Path -Leaf        
        if ((Test-Path $VHD_Path) -or ($VHD_Path.StartsWith("http"))) {
            Write-Host "ComputerName: $env:computername"
            Write-Host "VHD : $VHD_Path"
            #$VHD_Path = "\\redmond\wsscfs\OSTC\LIS\VHD\Cloudbase\CentOS\CentOS_7.2_x64\CentOS72x64.vhdx"
            .\Run-LisaV2.ps1 -TestPlatform HyperV `
                -XMLSecretFile '$env:Azure_Secrets_File' `
                -TestLocation localhost `
                -RGIdentifier DELETEME `
                -OsVHD $VHD_Path `
                -TestCategory $TestCategory `
                -TestArea $TestArea `
                -TestNames $TestNames `
                -VMGeneration $VMgeneration `
                -ForceDeleteResources `
                -ExitWithZero
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
