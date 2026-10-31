<#
.SYNOPSIS
Calls the WorldPlane control plane's API without showing the token.

.DESCRIPTION
  wp-api.ps1 METHOD PATH [JSON_BODY]
  wp-api.ps1 GET /v1/me
  wp-api.ps1 POST /v1/tenants/mystudio/projects/mygame/environments/test/deploy '{"build":"<id>"}'
  wp-api.ps1 GET /v1/tenants/mystudio/downloads/unreal-plugin -OutFile WorldPlane.zip

The URL and token come from WORLDPLANE_URL and WORLDPLANE_KEY (an API key or a
session token), else from the session `worldplane login` kept. The URL defaults
to https://app.worldplane.net. Prints the answer's body, or with -OutFile saves
it there (for downloads); exits 1 on an HTTP error, printing its status and
message. Don't send secret values through this: use `worldplane env secret set`,
which reads them unshown. Works in Windows PowerShell 5.1 and PowerShell 7.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Method,
    [Parameter(Mandatory = $true, Position = 1)][string]$Path,
    [Parameter(Position = 2)][string]$Body,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'

function Get-SessionFile {
    if ($env:WORLDPLANE_CONFIG_DIR) { return Join-Path $env:WORLDPLANE_CONFIG_DIR 'session.json' }
    if ($env:APPDATA) { return Join-Path $env:APPDATA 'worldplane\session.json' }
    if ($env:XDG_CONFIG_HOME) { return Join-Path $env:XDG_CONFIG_HOME 'worldplane/session.json' }
    return Join-Path $HOME '.config/worldplane/session.json'
}

$url = $env:WORLDPLANE_URL
$token = $env:WORLDPLANE_KEY
if (-not $token) {
    $file = Get-SessionFile
    if (-not (Test-Path $file)) {
        [Console]::Error.WriteLine("not signed in: run 'worldplane login --url https://app.worldplane.net --email <you>', or set WORLDPLANE_KEY")
        exit 1
    }
    $session = Get-Content -Raw $file | ConvertFrom-Json
    $token = $session.token
    if (-not $url) { $url = $session.url }
}
if (-not $url) { $url = 'https://app.worldplane.net' }
$url = $url.TrimEnd('/')
if (-not $Path.StartsWith('/')) { $Path = "/$Path" }

$request = @{
    Uri             = "$url$Path"
    Method          = $Method.ToUpperInvariant()
    Headers         = @{ Authorization = "Bearer $token" }
    UseBasicParsing = $true
}
if ($Body) {
    $request.ContentType = 'application/json'
    $request.Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
}
if ($OutFile) {
    # Resolved here: Invoke-WebRequest takes a relative path from the process's
    # directory, not PowerShell's.
    $request.OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
}
try {
    $response = Invoke-WebRequest @request
    if ($OutFile) {
        "saved $($request.OutFile)"
    } elseif ($response.Content) {
        if ($response.Content -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($response.Content)
        } else {
            $response.Content
        }
    }
    exit 0
} catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($null -eq $status) {
        [Console]::Error.WriteLine("the control plane at $url did not answer: $($_.Exception.Message)")
    } else {
        $message = $_.ErrorDetails.Message
        [Console]::Error.WriteLine("HTTP ${status}: $message")
    }
    exit 1
}
