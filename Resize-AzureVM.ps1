# -------------------------------
# User-configurable parameters
# -------------------------------
$params = @{
    SubscriptionId = "<YOUR_SUBSCRIPTION_ID>"
    ResourceGroup  = "<YOUR_RESOURCE_GROUP>"
    VMName         = "<YOUR_VM_NAME>"
    NewVmSize      = "Standard_DS2_v2" 
}

# -------------------------------
# Connect and Context
# -------------------------------
if (-not (Get-AzContext)) {
    Connect-AzAccount -ErrorAction Stop
}
Set-AzContext -SubscriptionId $params.SubscriptionId -ErrorAction Stop

# -------------------------------
# Execution Logic
# -------------------------------
try {
    $vm = Get-AzVM -ResourceGroupName $params.ResourceGroup -Name $params.VMName -Status -ErrorAction Stop
    
    $currentSize = $vm.HardwareProfile.VmSize
    Write-Host "Current VM Size: $currentSize"

    if ($currentSize -eq $params.NewVmSize) {
        Write-Warning "VM is already the requested size. Exiting."
        return
    }

    # Check if size is valid for this specific VM deployment
    $availableSizes = Get-AzVMSize -ResourceGroupName $params.ResourceGroup -VMName $params.VMName | Select-Object -ExpandProperty Name
    if ($params.NewVmSize -notin $availableSizes) {
        throw "The size '$($params.NewVmSize)' is not available for this VM in its current cluster."
    }

    # Update Logic
    Write-Host "Updating VM size to $($params.NewVmSize)..."
    $vm.HardwareProfile.VmSize = $params.NewVmSize
    
    # Update-AzVM will automatically restart the VM if it is running
    $vm | Update-AzVM -ErrorAction Stop
    
    Write-Host "Success! VM resized and restarting." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
}
