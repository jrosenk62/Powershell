# Script to create user folders and assign full control permissions

# Creates folders under \tree\sapling with user’s sAMAccountName

# Grants full control to each user for their respective folder

# Preserves inheritance settings from parent folder

# Define the base share path

$basePath = “\tree\sapling”

# Define the path to the text file containing usernames (one per line)

$userListFile = “C:\path\to\userlist.txt”

# Check if the user list file exists

if (-not (Test-Path -Path $userListFile)) {
Write-Host “Error: User list file not found at $userListFile” -ForegroundColor Red
Write-Host “Please create a text file with one username (sAMAccountName) per line.” -ForegroundColor Yellow
exit
}

# Read users from the text file

$users = Get-Content -Path $userListFile | Where-Object { $_.Trim() -ne “” }

# Process each user

foreach ($user in $users) {
try {
# Create the full folder path
$folderPath = Join-Path -Path $basePath -ChildPath $user

```
    # Check if folder already exists
    if (Test-Path -Path $folderPath) {
        Write-Host "Folder already exists: $folderPath" -ForegroundColor Yellow
    }
    else {
        # Create the folder
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        Write-Host "Created folder: $folderPath" -ForegroundColor Green
    }
    
    # Get the current ACL
    $acl = Get-Acl -Path $folderPath
    
    # Create the access rule for the user (Full Control)
    # FileSystemRights: FullControl
    # InheritanceFlags: ContainerInherit, ObjectInherit (applies to folder and files)
    # PropagationFlags: None
    # AccessControlType: Allow
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $user,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    
    # Add the access rule to the ACL (preserves existing inherited permissions)
    $acl.AddAccessRule($accessRule)
    
    # Apply the modified ACL to the folder
    Set-Acl -Path $folderPath -AclObject $acl
    
    Write-Host "Granted Full Control to $user on $folderPath" -ForegroundColor Green
}
catch {
    Write-Host "Error processing $user : $_" -ForegroundColor Red
}
```

}

Write-Host “`nScript completed!” -ForegroundColor Cyan
