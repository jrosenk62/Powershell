<#
.SYNOPSIS
    Creates an AWS EC2 instance with additional EBS volume(s) and mandatory tags.

.DESCRIPTION
    This script launches an EC2 instance from a specified AMI, attaches up to 5 additional
    EBS volumes, and applies five mandatory tags (name, system, owner, environment, billable)
    to the instance, all EBS volumes (including the root volume), and the network interface.
    All volumes are encrypted by default.

.PARAMETER AmiId
    The AMI ID to use for the instance

.PARAMETER InstanceType
    The EC2 instance type (default: t3.micro)

.PARAMETER KeyName
    The name of the SSH key pair

.PARAMETER SubnetId
    The subnet ID where the instance will be launched

.PARAMETER SecurityGroupId
    The security group ID(s) to assign

.PARAMETER AdditionalVolumeSize
    Size of the additional EBS volume in GB (default: 100). Used if -AdditionalVolumes is not specified.

.PARAMETER AdditionalVolumeType
    Type of additional EBS volume (default: gp3). Used if -AdditionalVolumes is not specified.

.PARAMETER AdditionalVolumes
    Array of hashtables defining additional volumes. Each hashtable should contain:
    - Size (required): Volume size in GB
    - Type (optional): Volume type (default: gp3)
    - Device (optional): Device name (auto-assigned if not specified)
    - Name (optional): Volume name suffix (default: data-N)
    - KmsKeyId (optional): KMS key ID for encryption (uses default EBS key if not specified)
    Maximum 5 volumes can be specified.

.PARAMETER KmsKeyId
    KMS key ID for encrypting volumes. If not specified, uses AWS default EBS encryption key.

.PARAMETER RootVolumeSize
    Size of the root volume in GB (optional, uses AMI default if not specified)

.PARAMETER RootVolumeType
    Type of root volume (default: gp3)

.PARAMETER RootDeviceName
    Device name for the root volume (default: /dev/xvda). Verify this matches your AMI's root device name.

.PARAMETER System
    Mandatory tag: System name

.PARAMETER Owner
    Mandatory tag: Owner name/email

.PARAMETER Environment
    Mandatory tag: Environment (e.g., dev, staging, prod)

.PARAMETER Billable
    Mandatory tag: Billable status (e.g., yes, no, department)

.PARAMETER Name
    Mandatory tag: Name of the instance

.EXAMPLE
    .\Create-EC2Instance.ps1 -AmiId "ami-0abcdef1234567890" -KeyName "mykey" `
        -SubnetId "subnet-12345" -SecurityGroupId "sg-12345" `
        -System "MyApp" -Owner "john.doe@example.com" -Environment "dev" -Billable "yes" `
        -Name "web-server-01"

.EXAMPLE
    # Create instance with multiple volumes
    $volumes = @(
        @{Size=100; Type="gp3"; Name="data"},
        @{Size=200; Type="gp3"; Name="logs"},
        @{Size=50; Type="gp2"; Name="temp"}
    )
    .\Create-EC2Instance.ps1 -AmiId "ami-0abcdef1234567890" -KeyName "mykey" `
        -SubnetId "subnet-12345" -SecurityGroupId "sg-12345" `
        -System "MyApp" -Owner "admin@example.com" -Environment "prod" -Billable "yes" `
        -Name "app-server-01" -AdditionalVolumes $volumes

.EXAMPLE
    # Create instance with custom KMS key for encryption
    .\Create-EC2Instance.ps1 -AmiId "ami-0abcdef1234567890" -KeyName "mykey" `
        -SubnetId "subnet-12345" -SecurityGroupId "sg-12345" `
        -System "SecureApp" -Owner "security@example.com" -Environment "prod" -Billable "yes" `
        -Name "secure-server-01" -KmsKeyId "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" `
        -RootVolumeSize 100 -RootVolumeType "gp3"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$AmiId,

    [Parameter(Mandatory=$false)]
    [string]$InstanceType = "t3.micro",

    [Parameter(Mandatory=$true)]
    [string]$KeyName,

    [Parameter(Mandatory=$true)]
    [string]$SubnetId,

    [Parameter(Mandatory=$true)]
    [string[]]$SecurityGroupId,

    [Parameter(Mandatory=$false)]
    [int]$AdditionalVolumeSize = 100,

    [Parameter(Mandatory=$false)]
    [string]$AdditionalVolumeType = "gp3",

    [Parameter(Mandatory=$false)]
    [hashtable[]]$AdditionalVolumes,

    [Parameter(Mandatory=$false)]
    [string]$KmsKeyId,

    [Parameter(Mandatory=$false)]
    [int]$RootVolumeSize,

    [Parameter(Mandatory=$false)]
    [string]$RootVolumeType = "gp3",

    [Parameter(Mandatory=$false)]
    [string]$RootDeviceName = "/dev/xvda",

    [Parameter(Mandatory=$true)]
    [string]$System,

    [Parameter(Mandatory=$true)]
    [string]$Owner,

    [Parameter(Mandatory=$true)]
    [ValidateSet("dev", "test", "staging", "prod", "qa")]
    [string]$Environment,

    [Parameter(Mandatory=$true)]
    [string]$Billable,

    [Parameter(Mandatory=$true)]
    [string]$Name
)

# Import AWS PowerShell module
Import-Module AWS.Tools.EC2

# Set AWS region (modify as needed or pass as parameter)
$Region = "us-east-1"
Set-DefaultAWSRegion -Region $Region

try {
    Write-Host "Creating EC2 instance with encrypted volumes..." -ForegroundColor Cyan

    # Validate additional volumes
    if ($AdditionalVolumes) {
        if ($AdditionalVolumes.Count -gt 5) {
            throw "Maximum of 5 additional volumes allowed. You specified $($AdditionalVolumes.Count)."
        }
        Write-Host "Will create $($AdditionalVolumes.Count) additional encrypted volume(s)" -ForegroundColor Cyan
    }

    # Create tags for the instance, volumes, and network interface
    $tags = @(
        @{Key="Name"; Value=$Name},
        @{Key="system"; Value=$System},
        @{Key="owner"; Value=$Owner},
        @{Key="environment"; Value=$Environment},
        @{Key="billable"; Value=$Billable}
    )

    # Convert tags to EC2 TagSpecification format
    $tagSpec = New-Object Amazon.EC2.Model.TagSpecification
    $tagSpec.ResourceType = "instance"
    foreach ($tag in $tags) {
        $ec2Tag = New-Object Amazon.EC2.Model.Tag
        $ec2Tag.Key = $tag.Key
        $ec2Tag.Value = $tag.Value
        $tagSpec.Tags.Add($ec2Tag)
    }

    # Create tag specification for volumes (applies to root volume at launch)
    $volumeTagSpec = New-Object Amazon.EC2.Model.TagSpecification
    $volumeTagSpec.ResourceType = "volume"
    foreach ($tag in $tags) {
        $ec2Tag = New-Object Amazon.EC2.Model.Tag
        $ec2Tag.Key = $tag.Key
        $ec2Tag.Value = $tag.Value
        $volumeTagSpec.Tags.Add($ec2Tag)
    }

    # Create tag specification for network interface
    $networkInterfaceTagSpec = New-Object Amazon.EC2.Model.TagSpecification
    $networkInterfaceTagSpec.ResourceType = "network-interface"
    foreach ($tag in $tags) {
        $ec2Tag = New-Object Amazon.EC2.Model.Tag
        $ec2Tag.Key = $tag.Key
        $ec2Tag.Value = $tag.Value
        $networkInterfaceTagSpec.Tags.Add($ec2Tag)
    }

    # Configure root volume with encryption
    $blockDeviceMapping = New-Object Amazon.EC2.Model.BlockDeviceMapping
    $blockDeviceMapping.DeviceName = $RootDeviceName
    
    $ebsBlockDevice = New-Object Amazon.EC2.Model.EbsBlockDevice
    $ebsBlockDevice.Encrypted = $true
    $ebsBlockDevice.DeleteOnTermination = $true
    $ebsBlockDevice.VolumeType = $RootVolumeType
    
    if ($RootVolumeSize) {
        $ebsBlockDevice.VolumeSize = $RootVolumeSize
    }
    
    if ($KmsKeyId) {
        $ebsBlockDevice.KmsKeyId = $KmsKeyId
        Write-Host "Root volume will be encrypted with KMS key: $KmsKeyId" -ForegroundColor Cyan
    } else {
        Write-Host "Root volume will be encrypted with default AWS EBS encryption key" -ForegroundColor Cyan
    }
    
    $blockDeviceMapping.Ebs = $ebsBlockDevice

    # Launch the EC2 instance
    # Tags applied at launch: instance, root volume, and network interface
    $instance = New-EC2Instance -ImageId $AmiId `
        -InstanceType $InstanceType `
        -KeyName $KeyName `
        -SubnetId $SubnetId `
        -SecurityGroupId $SecurityGroupId `
        -BlockDeviceMapping $blockDeviceMapping `
        -TagSpecification @($tagSpec, $volumeTagSpec, $networkInterfaceTagSpec) `
        -MinCount 1 `
        -MaxCount 1

    $instanceId = $instance.Instances[0].InstanceId
    Write-Host "Instance created with ID: $instanceId" -ForegroundColor Green

    # Wait for instance to be running
    Write-Host "Waiting for instance to enter 'running' state..." -ForegroundColor Yellow
    $null = Wait-EC2Instance -InstanceId $instanceId -DesiredState running -Timeout 300

    # Get instance details to find availability zone and network interface
    $instanceDetails = (Get-EC2Instance -InstanceId $instanceId).Instances[0]
    $availabilityZone = $instanceDetails.Placement.AvailabilityZone
    $networkInterfaceId = $instanceDetails.NetworkInterfaces[0].NetworkInterfaceId

    Write-Host "Instance is now running in AZ: $availabilityZone" -ForegroundColor Green
    Write-Host "Network Interface ID: $networkInterfaceId" -ForegroundColor Green

    # Verify network interface tags were applied (belt-and-suspenders check)
    # In rare cases where launch-time tagging doesn't propagate, this ensures tags are set
    $eniTagCheck = (Get-EC2NetworkInterface -NetworkInterfaceId $networkInterfaceId).TagSet
    if (-not $eniTagCheck -or $eniTagCheck.Count -eq 0) {
        Write-Host "Applying tags directly to network interface..." -ForegroundColor Yellow
        $eniTags = @()
        foreach ($tag in $tags) {
            $ec2Tag = New-Object Amazon.EC2.Model.Tag
            $ec2Tag.Key = $tag.Key
            $ec2Tag.Value = $tag.Value
            $eniTags += $ec2Tag
        }
        New-EC2Tag -Resource $networkInterfaceId -Tag $eniTags
        Write-Host "Network interface tags applied." -ForegroundColor Green
    }

    # Define available device names for additional volumes
    $deviceNames = @("/dev/sdf", "/dev/sdg", "/dev/sdh", "/dev/sdi", "/dev/sdj")
    $attachedVolumes = @()

    # Create additional EBS volumes
    if ($AdditionalVolumes -and $AdditionalVolumes.Count -gt 0) {
        for ($i = 0; $i -lt $AdditionalVolumes.Count; $i++) {
            $volConfig = $AdditionalVolumes[$i]
            
            # Validate required fields
            if (-not $volConfig.Size) {
                throw "Volume $($i+1): Size is required"
            }

            # Set defaults
            $volSize = $volConfig.Size
            $volType = if ($volConfig.Type) { $volConfig.Type } else { "gp3" }
            $volDevice = if ($volConfig.Device) { $volConfig.Device } else { $deviceNames[$i] }
            $volNameSuffix = if ($volConfig.Name) { $volConfig.Name } else { "data-$($i+1)" }
            $volKmsKeyId = if ($volConfig.KmsKeyId) { $volConfig.KmsKeyId } else { $KmsKeyId }

            Write-Host "`nCreating additional EBS volume $($i+1) of $($AdditionalVolumes.Count)..." -ForegroundColor Cyan
            Write-Host "  Size: $volSize GB, Type: $volType, Device: $volDevice, Encrypted: Yes" -ForegroundColor Gray
            
            $volumeTags = @()
            foreach ($tag in $tags) {
                $volumeTags += @{Key=$tag.Key; Value=$tag.Value}
            }
            $volumeTags += @{Key="Name"; Value="$Name-$volNameSuffix"}

            # Create volume with encryption
            if ($volKmsKeyId) {
                $volume = New-EC2Volume -AvailabilityZone $availabilityZone `
                    -Size $volSize `
                    -VolumeType $volType `
                    -Encrypted $true `
                    -KmsKeyId $volKmsKeyId `
                    -TagSpecification @{
                        ResourceType = "volume"
                        Tags = $volumeTags
                    }
                Write-Host "  Using KMS key: $volKmsKeyId" -ForegroundColor Gray
            } else {
                $volume = New-EC2Volume -AvailabilityZone $availabilityZone `
                    -Size $volSize `
                    -VolumeType $volType `
                    -Encrypted $true `
                    -TagSpecification @{
                        ResourceType = "volume"
                        Tags = $volumeTags
                    }
                Write-Host "  Using default AWS EBS encryption key" -ForegroundColor Gray
            }

            $volumeId = $volume.VolumeId
            Write-Host "  Volume created with ID: $volumeId" -ForegroundColor Green

            # Wait for volume to be available
            Write-Host "  Waiting for volume to be available..." -ForegroundColor Yellow
            do {
                Start-Sleep -Seconds 2
                $volumeState = (Get-EC2Volume -VolumeId $volumeId).State
            } while ($volumeState -ne "available")

            # Attach volume to instance
            Write-Host "  Attaching volume to instance at $volDevice..." -ForegroundColor Cyan
            $attachment = Add-EC2Volume -InstanceId $instanceId `
                -VolumeId $volumeId `
                -Device $volDevice

            Write-Host "  Volume attached successfully!" -ForegroundColor Green

            # Store volume info for summary
            $attachedVolumes += @{
                VolumeId = $volumeId
                Size = $volSize
                Type = $volType
                Device = $volDevice
                Name = "$Name-$volNameSuffix"
                Encrypted = $true
                KmsKeyId = if ($volKmsKeyId) { $volKmsKeyId } else { "Default AWS EBS key" }
            }
        }
    } else {
        # Fallback to original single volume behavior if no AdditionalVolumes specified
        Write-Host "`nCreating additional encrypted EBS volume..." -ForegroundColor Cyan
        
        $volumeTags = @()
        foreach ($tag in $tags) {
            $volumeTags += @{Key=$tag.Key; Value=$tag.Value}
        }
        $volumeTags += @{Key="Name"; Value="$Name-data"}

        # Create volume with encryption
        if ($KmsKeyId) {
            $volume = New-EC2Volume -AvailabilityZone $availabilityZone `
                -Size $AdditionalVolumeSize `
                -VolumeType $AdditionalVolumeType `
                -Encrypted $true `
                -KmsKeyId $KmsKeyId `
                -TagSpecification @{
                    ResourceType = "volume"
                    Tags = $volumeTags
                }
            Write-Host "Using KMS key: $KmsKeyId" -ForegroundColor Gray
        } else {
            $volume = New-EC2Volume -AvailabilityZone $availabilityZone `
                -Size $AdditionalVolumeSize `
                -VolumeType $AdditionalVolumeType `
                -Encrypted $true `
                -TagSpecification @{
                    ResourceType = "volume"
                    Tags = $volumeTags
                }
            Write-Host "Using default AWS EBS encryption key" -ForegroundColor Gray
        }

        $volumeId = $volume.VolumeId
        Write-Host "Volume created with ID: $volumeId" -ForegroundColor Green

        # Wait for volume to be available
        Write-Host "Waiting for volume to be available..." -ForegroundColor Yellow
        do {
            Start-Sleep -Seconds 2
            $volumeState = (Get-EC2Volume -VolumeId $volumeId).State
        } while ($volumeState -ne "available")

        # Attach volume to instance
        Write-Host "Attaching volume to instance..." -ForegroundColor Cyan
        $attachment = Add-EC2Volume -InstanceId $instanceId `
            -VolumeId $volumeId `
            -Device "/dev/sdf"

        Write-Host "Volume attached successfully!" -ForegroundColor Green

        # Store volume info for summary
        $attachedVolumes += @{
            VolumeId = $volumeId
            Size = $AdditionalVolumeSize
            Type = $AdditionalVolumeType
            Device = "/dev/sdf"
            Name = "$Name-data"
            Encrypted = $true
            KmsKeyId = if ($KmsKeyId) { $KmsKeyId } else { "Default AWS EBS key" }
        }
    }

    # Display summary
    Write-Host "`n=== EC2 Instance Summary ===" -ForegroundColor Cyan
    Write-Host "Instance ID: $instanceId"
    Write-Host "Instance Type: $InstanceType"
    Write-Host "Private IP: $($instanceDetails.PrivateIpAddress)"
    Write-Host "Public IP: $($instanceDetails.PublicIpAddress)"
    Write-Host "Availability Zone: $availabilityZone"
    Write-Host "Network Interface ID: $networkInterfaceId"
    
    Write-Host "`nRoot Volume:"
    Write-Host "  Encrypted: Yes"
    Write-Host "  Type: $RootVolumeType"
    if ($RootVolumeSize) {
        Write-Host "  Size: $RootVolumeSize GB"
    }
    if ($KmsKeyId) {
        Write-Host "  KMS Key: $KmsKeyId"
    } else {
        Write-Host "  KMS Key: Default AWS EBS key"
    }

    Write-Host "`nAttached Volumes:"
    foreach ($vol in $attachedVolumes) {
        Write-Host "  - $($vol.Name)"
        Write-Host "    Volume ID: $($vol.VolumeId)"
        Write-Host "    Size: $($vol.Size) GB"
        Write-Host "    Type: $($vol.Type)"
        Write-Host "    Device: $($vol.Device)"
        Write-Host "    Encrypted: $($vol.Encrypted)"
        Write-Host "    KMS Key: $($vol.KmsKeyId)"
    }
    
    Write-Host "`nTags (applied to instance, all volumes, and network interface):"
    foreach ($tag in $tags) {
        Write-Host "  $($tag.Key): $($tag.Value)"
    }

} catch {
    Write-Host "Error occurred: $_" -ForegroundColor Red
    throw
}
