# --- Configuration ---
$vaultName = "MyRecoveryServicesVault"
$vaultRG = "BackupResourceGroup"
$targetRG = "bcp-rg"
$location = "EastUS" # Use the same region as your vault

# Staging Storage (Mandatory for VM Restore)
$stagingStorageName = "mystagingstorageacct"
$stagingStorageRG = "BackupResourceGroup"

# Networking for Restored VMs
$targetVnetName = "bcp-vnet"
$targetVnetRG = "bcp-rg"
$targetSubnetName = "default"

# --- Execution ---

# 1. Set the Vault Context
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultRG -Name $vaultName
Set-AzRecoveryServicesVaultContext -Vault $vault

# 2. Create the Target Resource Group if it doesn't exist
if (!(Get-AzResourceGroup -Name $targetRG -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $targetRG -Location $location
    Write-Host "Created Resource Group: $targetRG" -ForegroundColor Cyan
}

# 3. Get all VM Backup Items
$backupItems = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM

foreach ($item in $backupItems) {
    Write-Host "Processing Restore for: $($item.FriendlyName)..." -ForegroundColor Yellow
    
    # 4. Get the latest Recovery Point
    $recoveryPoint = Get-AzRecoveryServicesBackupRecoveryPoint -Item $item | 
                     Sort-Object RecoveryPointTime -Descending | 
                     Select-Object -First 1

    if ($null -ne $recoveryPoint) {
        # 5. Trigger the Restore Job
        # Note: -TargetVMName must be unique if the original VM still exists in the subscription
        $restoreJob = Restore-AzRecoveryServicesBackupItem `
            -RecoveryPoint $recoveryPoint `
            -StorageAccountName $stagingStorageName `
            -StorageAccountResourceGroupName $stagingStorageRG `
            -TargetResourceGroupName $targetRG `
            -TargetVMName "$($item.FriendlyName)-restored" `
            -TargetVNetName $targetVnetName `
            -TargetVNetResourceGroup $targetVnetRG `
            -TargetSubnetName $targetSubnetName

        Write-Host "Restore job submitted for $($item.FriendlyName). Job ID: $($restoreJob.JobId)" -ForegroundColor Green
    } else {
        Write-Warning "No recovery points found for $($item.FriendlyName)"
    }
}
