# ============================================================
# What the Script Does
# For each group-to-team mapping, it runs these steps in order:

# 1. Authenticates with Entra ID via client credentials (app registration)
# 2. Loads all Grafana org users once via /api/org/users into a hashtable for efficient lookup
# 3. Reads group members from Entra ID via Microsoft Graph API (with pagination support)
# 4. Creates the Grafana team if it doesn't exist
# 5. Adds members to the team — additive only, skips existing members
# 6. Creates a dashboard folder with the same name as the team
# 7. Assigns the team Admin permission on that folder
# ============================================================

# ============================================================
# Note: Export below variables if you are testing it locally
# $env:ENTRA_TENANT_ID     = "<YOUR TENANT ID>"
# $env:ENTRA_CLIENT_ID     = "<YOUR CLIENT ID>"
# $env:ENTRA_CLIENT_SECRET = "<YOUR_CLIENT_SECRET>"
# $env:GRAFANA_URL         = "https://mytestdomain.co.in"   # or your Grafana URL
# $env:GRAFANA_TOKEN       = "<YOUR GRAFANA TOKEN>"
# ============================================================


# ============================================================
# sync-grafana-teams.ps1
# Reads Entra ID group members, adds them to Grafana Teams,
# creates a Dashboard folder and assigns Admin permission
# ============================================================

param (
    [string]$TenantId       = $env:ENTRA_TENANT_ID,
    [string]$ClientId       = $env:ENTRA_CLIENT_ID,
    [string]$ClientSecret   = $env:ENTRA_CLIENT_SECRET,
    [string]$GrafanaUrl     = $env:GRAFANA_URL,
    [string]$GrafanaToken   = $env:GRAFANA_TOKEN,
    [string[]]$TargetGroups = @()
)

# Force TLS 1.2 - required for Microsoft Graph API and Grafana
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Validate inputs
$missing = @()
if (-not $TenantId)     { $missing += "ENTRA_TENANT_ID" }
if (-not $ClientId)     { $missing += "ENTRA_CLIENT_ID" }
if (-not $ClientSecret) { $missing += "ENTRA_CLIENT_SECRET" }
if (-not $GrafanaUrl)   { $missing += "GRAFANA_URL" }
if (-not $GrafanaToken) { $missing += "GRAFANA_TOKEN" }

if ($missing.Count -gt 0) {
    Write-Error "Missing required environment variables: $($missing -join ', ')"
    exit 1
}

# Group-to-Team mapping
# Format: "Entra Group Display Name" = "Grafana Team Name"
# Folder name will match the Grafana Team Name
$GroupTeamMapping = @{
    "grafanaviewer" = "viewer"
}

# Grafana Headers
$GrafanaHeaders = @{
    "Authorization" = "Bearer $GrafanaToken"
    "Content-Type"  = "application/json"
}

# Get Entra ID Access Token
function Get-EntraToken {
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }
    try {
        $response = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method POST `
            -Body $body
        return $response.access_token
    } catch {
        Write-Error "Failed to acquire Entra ID token. Check TenantId, ClientId and ClientSecret."
        Write-Error "Details: $_"
        exit 1
    }
}

# Get Entra ID Group by Display Name
function Get-EntraGroup {
    param([string]$Token, [string]$GroupName)
    $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'&`$select=id,displayName"
    try {
        $response = Invoke-RestMethod `
            -Uri $uri `
            -Headers @{ Authorization = "Bearer $Token" } `
            -Method GET
        if ($response.value.Count -eq 0) {
            Write-Warning "[ENTRA] Group $GroupName not found. Verify the exact display name in Entra ID."
            return $null
        }
        return $response.value[0]
    } catch {
        Write-Error "[ENTRA] Error looking up group $GroupName - $_"
        return $null
    }
}

# Get Group Members from Entra ID (with pagination)
function Get-EntraGroupMembers {
    param([string]$Token, [string]$GroupId)
    $members = @()
    $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members?`$select=displayName,mail,userPrincipalName"
    while ($uri) {
        $response = Invoke-RestMethod `
            -Uri $uri `
            -Headers @{ Authorization = "Bearer $Token" } `
            -Method GET
        foreach ($m in $response.value) {
            if (-not $m.mail -and $m.userPrincipalName) {
                $m | Add-Member -NotePropertyName 'mail' -NotePropertyValue $m.userPrincipalName -Force
            }
        }
        $members += $response.value | Where-Object { $_.mail -ne $null }
        $uri = $response.'@odata.nextLink'
    }
    return $members
}

# Get all Grafana org users into a hashtable keyed by email (single API call)
function Get-GrafanaOrgUsers {
    try {
        $response = Invoke-RestMethod `
            -Uri "$GrafanaUrl/api/org/users" `
            -Headers $GrafanaHeaders `
            -Method GET
        $lookup = @{}
        foreach ($u in $response) {
            if ($u.email) {
                $lookup[$u.email.ToLower()] = $u
            }
        }
        Write-Host "  [GRAFANA] Loaded $($lookup.Count) org users"
        return $lookup
    } catch {
        Write-Error "[GRAFANA] Failed to load org users - $_"
        exit 1
    }
}

# Get or Create Grafana Team
function Get-OrCreate-GrafanaTeam {
    param([string]$TeamName)
    $encodedName  = [System.Web.HttpUtility]::UrlEncode($TeamName)
    $searchResult = Invoke-RestMethod `
        -Uri "$GrafanaUrl/api/teams/search?name=$encodedName" `
        -Headers $GrafanaHeaders `
        -Method GET
    $existing = $searchResult.teams | Where-Object { $_.name -eq $TeamName }
    if ($existing) {
        Write-Host "  [GRAFANA] Team $TeamName exists (id: $($existing.id))"
        return $existing.id
    }
    Write-Host "  [GRAFANA] Creating team $TeamName ..."
    $body         = @{ name = $TeamName } | ConvertTo-Json
    $createResult = Invoke-RestMethod `
        -Uri "$GrafanaUrl/api/teams" `
        -Headers $GrafanaHeaders `
        -Method POST `
        -Body $body
    Write-Host "  [GRAFANA] Team $TeamName created (id: $($createResult.teamId))"
    return $createResult.teamId
}

# Get existing Grafana Team Members
function Get-GrafanaTeamMembers {
    param([int]$TeamId)
    $response = Invoke-RestMethod `
        -Uri "$GrafanaUrl/api/teams/$TeamId/members" `
        -Headers $GrafanaHeaders `
        -Method GET
    return $response | ForEach-Object { $_.email.ToLower() }
}

# Add User to Grafana Team
function Add-UserToGrafanaTeam {
    param([int]$TeamId, [int]$UserId, [string]$Email)
    $body = @{ userId = $UserId } | ConvertTo-Json
    try {
        Invoke-RestMethod `
            -Uri "$GrafanaUrl/api/teams/$TeamId/members" `
            -Headers $GrafanaHeaders `
            -Method POST `
            -Body $body | Out-Null
        Write-Host "    [+] Added $Email to team"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "    [~] $Email already in team, skipping"
        } else {
            Write-Warning "    [!] Failed to add $Email - $_"
        }
    }
}

# Get or Create Grafana Folder
function Get-OrCreate-GrafanaFolder {
    param([string]$FolderName)
    try {
        $allFolders = Invoke-RestMethod `
            -Uri "$GrafanaUrl/api/folders" `
            -Headers $GrafanaHeaders `
            -Method GET
        $existing = $allFolders | Where-Object { $_.title -eq $FolderName }
        if ($existing) {
            Write-Host "  [GRAFANA] Folder '$FolderName' exists (uid: $($existing.uid))"
            return $existing.uid
        }
        Write-Host "  [GRAFANA] Creating folder '$FolderName' ..."
        $body   = @{ title = $FolderName } | ConvertTo-Json
        $result = Invoke-RestMethod `
            -Uri "$GrafanaUrl/api/folders" `
            -Headers $GrafanaHeaders `
            -Method POST `
            -Body $body
        Write-Host "  [GRAFANA] Folder '$FolderName' created (uid: $($result.uid))"
        return $result.uid
    } catch {
        Write-Error "  [GRAFANA] Failed to get/create folder '$FolderName' - $_"
        return $null
    }
}

# Assign Team Admin permission on a Folder
# Permission levels: 1=View, 2=Edit, 4=Admin
function Set-GrafanaFolderTeamPermission {
    param([string]$FolderUid, [int]$TeamId, [string]$TeamName, [string]$FolderName)

    # Get existing folder permissions
    $existing = Invoke-RestMethod `
        -Uri "$GrafanaUrl/api/folders/$FolderUid/permissions" `
        -Headers $GrafanaHeaders `
        -Method GET

    # Check if team permission already exists with Admin
    $alreadySet = $existing | Where-Object { $_.teamId -eq $TeamId -and $_.permission -eq 4 }
    if ($alreadySet) {
        Write-Host "  [GRAFANA] Team $TeamName already has Admin on folder '$FolderName', skipping"
        return
    }

    # Preserve existing permissions, exclude old entry for this team if any
    $permissions = @()
    foreach ($p in $existing) {
        if ($p.teamId -eq $TeamId) { continue }
        if ($p.teamId -and $p.teamId -gt 0) {
            $permissions += @{ teamId = [int]$p.teamId; permission = [int]$p.permission }
        } elseif ($p.userId -and $p.userId -gt 0) {
            $permissions += @{ userId = [int]$p.userId; permission = [int]$p.permission }
        } elseif ($p.builtInRole) {
            $permissions += @{ builtInRole = $p.builtInRole; permission = [int]$p.permission }
        }
    }

    # Add team with Admin (4)
    $permissions += @{ teamId = [int]$TeamId; permission = 4 }

    $body = @{ items = $permissions } | ConvertTo-Json -Depth 5
    Write-Host "  [DEBUG] Permission payload: $body"

    try {
        Invoke-RestMethod `
            -Uri "$GrafanaUrl/api/folders/$FolderUid/permissions" `
            -Headers $GrafanaHeaders `
            -Method POST `
            -Body $body | Out-Null
        Write-Host "  [GRAFANA] Team $TeamName granted Admin on folder '$FolderName'"
    } catch {
        Write-Warning "  [GRAFANA] Failed to set folder permission - $_"
    }
}

# MAIN
Write-Host "================================================"
Write-Host " Grafana Teams Sync - Starting"
Write-Host "================================================"

Write-Host ""
Write-Host "[1] Authenticating with Entra ID..."
$entraToken = Get-EntraToken
Write-Host "    Token acquired successfully."

Write-Host ""
Write-Host "[2] Loading Grafana org users..."
$grafanaUsers = Get-GrafanaOrgUsers

$mappingToProcess = $GroupTeamMapping

if ($TargetGroups.Count -gt 0) {
    Write-Host ""
    Write-Host "[3] Filtering to specified groups: $($TargetGroups -join ', ')"
    $mappingToProcess = @{}
    foreach ($g in $TargetGroups) {
        if ($GroupTeamMapping.ContainsKey($g)) {
            $mappingToProcess[$g] = $GroupTeamMapping[$g]
        } else {
            Write-Warning "  [!] $g not found in GroupTeamMapping. Skipping."
        }
    }
    if ($mappingToProcess.Count -eq 0) {
        Write-Error "None of the specified TargetGroups exist in GroupTeamMapping. Exiting."
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "[3] No TargetGroups specified - syncing ALL groups in mapping."
}

foreach ($entry in $mappingToProcess.GetEnumerator()) {
    $entraGroupName  = $entry.Key
    $grafanaTeamName = $entry.Value
    $folderName      = $grafanaTeamName   # Folder name matches team name

    Write-Host ""
    Write-Host "------------------------------------------------"
    Write-Host " Syncing: $entraGroupName => $grafanaTeamName"
    Write-Host "------------------------------------------------"

    # Step A: Get Entra group and members
    $group = Get-EntraGroup -Token $entraToken -GroupName $entraGroupName
    if (-not $group) { continue }

    $members = Get-EntraGroupMembers -Token $entraToken -GroupId $group.id
    Write-Host "  [ENTRA] Found $($members.Count) members"

    # Step B: Get or create Grafana team
    $teamId = Get-OrCreate-GrafanaTeam -TeamName $grafanaTeamName

    # Step C: Sync members into team
    if ($members.Count -eq 0) {
        Write-Host "  No members to sync."
    } else {
        $existingEmails = Get-GrafanaTeamMembers -TeamId $teamId
        foreach ($member in $members) {
            $email = $member.mail.ToLower()
            Write-Host "  Processing: $email"
            if ($existingEmails -contains $email) {
                Write-Host "    [~] Already in team, skipping"
                continue
            }
            $grafanaUser = $grafanaUsers[$email]
            if (-not $grafanaUser) {
                Write-Warning "    [!] $email not found in Grafana. User may not have logged in via SSO yet."
                continue
            }
            Add-UserToGrafanaTeam -TeamId $teamId -UserId $grafanaUser.userId -Email $email
        }
    }

    # Step D: Get or create folder with same name as team
    Write-Host ""
    Write-Host "  [FOLDER] Setting up dashboard folder '$folderName'..."
    $folderUid = Get-OrCreate-GrafanaFolder -FolderName $folderName
    if (-not $folderUid) {
        Write-Warning "  Skipping folder permission - folder could not be created."
        continue
    }

    # Step E: Assign team Admin permission on folder
    Set-GrafanaFolderTeamPermission -FolderUid $folderUid -TeamId $teamId -TeamName $grafanaTeamName -FolderName $folderName
}

Write-Host ""
Write-Host "================================================"
Write-Host " Sync Complete"
Write-Host "================================================"
