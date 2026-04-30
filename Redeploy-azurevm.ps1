# ---------------------------------------------------------
# Variables & Configuration
# ---------------------------------------------------------
$ResourceGroupName = "YourResourceGroupName"
$VMName            = "YourVMName"
$Location          = "EastUS" 
$NewImageSku       = "2022-datacenter-g2"
$AdminUsername     = "AzureAdmin"
$DryRun            = $true  # Set to $false to actually execute deletions

# ---------------------------------------------------------
# 1. Capture Current Configuration & Identify OS Disk
# ---------------------------------------------------------
Write-Host "[LOG] Fetching current configuration for $VMName..." -ForegroundColor Cyan
$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName

if (-not $vm) { throw "VM $VMName not found." }

# Identify the OS Disk ID for later deletion
$oldOsDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
$vmSize      = $vm.HardwareProfile.VmSize
$nicId       = $vm.NetworkProfile.NetworkInterfaces[0].Id
$dataDisks   = $vm.StorageProfile.DataDisks

Write-Host "[LOG] Old OS Disk identified: $oldOsDiskId" -ForegroundColor Yellow

# ---------------------------------------------------------
# 2. Delete the VM and then the OS Disk
# ---------------------------------------------------------
if (-not $DryRun) {
    Write-Host "[LOG] Deleting VM..." -ForegroundColor Red
    Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force
    
    Write-Host "[LOG] Deleting old OS disk..." -ForegroundColor Red
    Remove-AzDisk -ResourceId $oldOsDiskId -Force
} else {
    Write-Host "[DRY RUN] Would delete VM: $VMName" -ForegroundColor Gray
    Write-Host "[DRY RUN] Would delete OS Disk: $oldOsDiskId" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 3. Deploy New VM (Same NIC and Data Disks)
# ---------------------------------------------------------
Write-Host "[LOG] Building new VM configuration..." -ForegroundColor Cyan

$cred = if ($DryRun) { $null } else { Get-Credential -UserName $AdminUsername }

$newVmConfig = New-AzVMConfig -VMName $VMName -VMSize $vmSize | `
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus $NewImageSku -Version "latest" | `
    Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $cred -ProvisionVMAgent | `
    Add-AzVMNetworkInterface -Id $nicId

foreach ($disk in $dataDisks) {
    $newVmConfig = Add-AzVMDataDisk -VM $newVmConfig -Name $disk.Name -ManagedDiskId $disk.ManagedDisk.Id -Lun $disk.Lun -Caching $disk.Caching -CreateOption Attach
}

if (-not $DryRun) {
    Write-Host "[LOG] Deploying Windows Server 2022..." -ForegroundColor Magenta
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $newVmConfig
} else {
    Write-Host "[DRY RUN] Deployment step skipped." -ForegroundColor Gray
}
