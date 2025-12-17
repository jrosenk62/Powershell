<#
.SYNOPSIS
    Creates an AWS EC2 instance with additional EBS volume and mandatory tags.

.DESCRIPTION
    This script launches an EC2 instance from a specified AMI, attaches an additional
    EBS volume, and applies four mandatory tags: system, owner, environment, and billable.

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
    Size of the additional EBS volume in GB (default: 100)

.PARAMETER AdditionalVolumeType
    Type of additional EBS volume (default: gp3)

.PARAMETER System
    Mandatory tag: System name

.PARAMETER Owner
    Mandatory tag: Owner name/email

.PARAMETER Environment
    Mandatory tag: Environment (e.g., dev, staging, prod)

.PARAMETER Billable
    Mandatory tag: Billable status (e.g., yes, no, department)

.EXAMPLE
    .\Create-EC2Instance.ps1 -AmiId "ami-0abcdef1234567890" -KeyName "mykey" `
        -SubnetId "subnet-12345" -SecurityGroupId "sg-12345" `
        -System "MyApp" -Owner "john.doe@example.com" -Environment "dev" -Billable "yes"
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

    [Parameter(Mandatory=$true)]
    [string]$System,

    [Parameter(Mandatory=$true)]
    [string]$Owner,

    [Parameter(Mandatory=$true)]
    [ValidateSet("dev", "test", "staging", "prod", "qa")]
    [string]$Environment,

    [Parameter(Mandatory=$true)]
    [string]$Billable
)

# Import AWS PowerShell module
Import-Module AWS.Tools.EC2

# Set AWS region (modify as needed or pass as parameter)
$Region = "us-east-1"
Set-DefaultAWSRegion -Region $Region

try {
    Write-Host "Creating EC2 instance..." -ForegroundColor Cyan

    # Create tags for the instance and volumes
    $tags = @(
        @{Key="Name"; Value="$System-$Environment"},
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

    # Create tag specification for volumes
    $volumeTagSpec = New-Object Amazon.EC2.Model.TagSpecification
    $volumeTagSpec.ResourceType = "volume"
    foreach ($tag in $tags) {
        $ec2Tag = New-Object Amazon.EC2.Model.Tag
        $ec2Tag.Key = $tag.Key
        $ec2Tag.Value = $tag.Value
        $volumeTagSpec.Tags.Add($ec2Tag)
    }

    # Launch the EC2 instance
    $instance = New-EC2Instance -ImageId $AmiId `
        -InstanceType $InstanceType `
        -KeyName $KeyName `
        -SubnetId $SubnetId `
        -SecurityGroupId $SecurityGroupId `
        -TagSpecification @($tagSpec, $volumeTagSpec) `
        -MinCount 1 `
        -MaxCount 1

    $instanceId = $instance.Instances[0].InstanceId
    Write-Host "Instance created with ID: $instanceId" -ForegroundColor Green

    # Wait for instance to be running
    Write-Host "Waiting for instance to enter 'running' state..." -ForegroundColor Yellow
    $null = Wait-EC2Instance -InstanceId $instanceId -DesiredState running -Timeout 300

    # Get instance details to find availability zone
    $instanceDetails = (Get-EC2Instance -InstanceId $instanceId).Instances[0]
    $availabilityZone = $instanceDetails.Placement.AvailabilityZone

    Write-Host "Instance is now running in AZ: $availabilityZone" -ForegroundColor Green

    # Create additional EBS volume
    Write-Host "Creating additional EBS volume..." -ForegroundColor Cyan
    
    $volumeTags = @()
    foreach ($tag in $tags) {
        $volumeTags += @{Key=$tag.Key; Value=$tag.Value}
    }
    $volumeTags += @{Key="Name"; Value="$System-$Environment-data"}

    $volume = New-EC2Volume -AvailabilityZone $availabilityZone `
        -Size $AdditionalVolumeSize `
        -VolumeType $AdditionalVolumeType `
        -TagSpecification @{
            ResourceType = "volume"
            Tags = $volumeTags
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

    # Display summary
    Write-Host "`n=== EC2 Instance Summary ===" -ForegroundColor Cyan
    Write-Host "Instance ID: $instanceId"
    Write-Host "Instance Type: $InstanceType"
    Write-Host "Private IP: $($instanceDetails.PrivateIpAddress)"
    Write-Host "Public IP: $($instanceDetails.PublicIpAddress)"
    Write-Host "Availability Zone: $availabilityZone"
    Write-Host "Additional Volume ID: $volumeId"
    Write-Host "Volume Size: $AdditionalVolumeSize GB"
    Write-Host "Device Name: /dev/sdf"
    Write-Host "`nTags:"
    foreach ($tag in $tags) {
        Write-Host "  $($tag.Key): $($tag.Value)"
    }

} catch {
    Write-Host "Error occurred: $_" -ForegroundColor Red
    throw
}
