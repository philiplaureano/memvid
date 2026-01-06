#Requires -Version 5.1
<#
.SYNOPSIS
    memvid-mcp Installer for Windows
.DESCRIPTION
    Configures memvid memory for Claude Desktop, Claude Code, and GitHub Copilot CLI
.PARAMETER MemoryPath
    Custom memory file location (default: $HOME\.memvid\memory.mv2)
.PARAMETER Client
    Configure only one client (claude-desktop, claude-code, copilot-cli)
.PARAMETER DryRun
    Show what would happen without making changes
.PARAMETER Uninstall
    Remove memvid from all clients
.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -MemoryPath "D:\data\memory.mv2"
.EXAMPLE
    .\install.ps1 -Client claude-code
.EXAMPLE
    .\install.ps1 -Uninstall
#>

param(
    [string]$MemoryPath,
    [ValidateSet("claude-desktop", "claude-code", "copilot-cli", "")]
    [string]$Client = "",
    [switch]$DryRun,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$VERSION = "1.0.0"
$DEFAULT_MEMORY_PATH = Join-Path $HOME ".memvid\memory.mv2"

# Set memory path to default if not specified
if ([string]::IsNullOrEmpty($MemoryPath)) {
    $MemoryPath = $DEFAULT_MEMORY_PATH
}

# Config paths
$CLAUDE_DESKTOP_CONFIG = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$COPILOT_CLI_CONFIG = Join-Path $HOME ".copilot\mcp-config.json"

function Write-Success { param([string]$Message) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warning { param([string]$Message) Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Failure { param([string]$Message) Write-Host "[X] " -ForegroundColor Red -NoNewline; Write-Host $Message }

function Test-ClaudeDesktopInstalled {
    $configDir = Split-Path $CLAUDE_DESKTOP_CONFIG -Parent
    return (Test-Path $configDir) -or (Test-Path $CLAUDE_DESKTOP_CONFIG)
}

function Test-ClaudeCodeInstalled {
    $claudeCmd = Get-Command "claude" -ErrorAction SilentlyContinue
    return $null -ne $claudeCmd
}

function Test-CopilotCliInstalled {
    $copilotDir = Join-Path $HOME ".copilot"
    $copilotCmd = Get-Command "copilot" -ErrorAction SilentlyContinue
    return (Test-Path $copilotDir) -or ($null -ne $copilotCmd)
}

function Merge-MemvidConfig {
    param(
        [string]$ConfigFile,
        [hashtable]$MemvidEntry
    )

    # Read existing config or create new
    $config = @{}
    if (Test-Path $ConfigFile) {
        try {
            $content = Get-Content $ConfigFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $config = $content | ConvertFrom-Json -AsHashtable
            }
        } catch {
            $config = @{}
        }
    }

    # Ensure mcpServers exists
    if (-not $config.ContainsKey("mcpServers")) {
        $config["mcpServers"] = @{}
    }

    # Add or update memvid
    $config["mcpServers"]["memvid"] = $MemvidEntry

    # Write back
    $configDir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8
}

function Remove-MemvidConfig {
    param([string]$ConfigFile)

    if (-not (Test-Path $ConfigFile)) {
        return
    }

    try {
        $content = Get-Content $ConfigFile -Raw
        if ([string]::IsNullOrWhiteSpace($content)) {
            return
        }

        $config = $content | ConvertFrom-Json -AsHashtable

        if ($config.ContainsKey("mcpServers") -and $config["mcpServers"].ContainsKey("memvid")) {
            $config["mcpServers"].Remove("memvid")
            $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8
        }
    } catch {
        # Ignore errors
    }
}

function New-MemoryFile {
    if ($DryRun) {
        Write-Host "[DRY RUN] Would create: $MemoryPath"
        return
    }

    $memoryDir = Split-Path $MemoryPath -Parent
    if (-not (Test-Path $memoryDir)) {
        New-Item -ItemType Directory -Path $memoryDir -Force | Out-Null
    }

    if (-not (Test-Path $MemoryPath)) {
        # Create empty mv2 file (memvid will initialize it on first use)
        New-Item -ItemType File -Path $MemoryPath -Force | Out-Null
        Write-Success "Created $MemoryPath"
    } else {
        Write-Success "Memory file exists: $MemoryPath"
    }
}

function Install-ClaudeDesktop {
    if (-not [string]::IsNullOrEmpty($Client) -and $Client -ne "claude-desktop") {
        return
    }

    if (-not (Test-ClaudeDesktopInstalled)) {
        Write-Host "Claude Desktop not detected, skipping"
        return
    }

    # Windows requires cmd /c wrapper for npx
    $memvidEntry = @{
        command = "cmd"
        args = @("/c", "npx", "-y", "@philiplaureano/memvid-mcp")
        env = @{
            MEMVID_DEFAULT_PATH = $MemoryPath
        }
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] Would configure Claude Desktop: $CLAUDE_DESKTOP_CONFIG"
        return
    }

    if ($Uninstall) {
        Remove-MemvidConfig -ConfigFile $CLAUDE_DESKTOP_CONFIG
        Write-Success "Removed memvid from Claude Desktop"
    } else {
        Merge-MemvidConfig -ConfigFile $CLAUDE_DESKTOP_CONFIG -MemvidEntry $memvidEntry
        Write-Success "Configured Claude Desktop ($CLAUDE_DESKTOP_CONFIG)"
    }
}

function Install-ClaudeCode {
    if (-not [string]::IsNullOrEmpty($Client) -and $Client -ne "claude-code") {
        return
    }

    if (-not (Test-ClaudeCodeInstalled)) {
        Write-Host "Claude Code not detected, skipping"
        return
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] Would configure Claude Code via: claude mcp add-json"
        return
    }

    if ($Uninstall) {
        try {
            & claude mcp remove memvid 2>$null
        } catch { }
        Write-Success "Removed memvid from Claude Code"
    } else {
        # Remove existing first (if any)
        try {
            & claude mcp remove memvid 2>$null
        } catch { }

        # Windows requires cmd /c wrapper for npx
        $mcpJson = @{
            command = "cmd"
            args = @("/c", "npx", "-y", "@philiplaureano/memvid-mcp")
            env = @{
                MEMVID_DEFAULT_PATH = $MemoryPath
            }
        } | ConvertTo-Json -Compress

        & claude mcp add-json memvid $mcpJson --scope user
        Write-Success "Configured Claude Code"
    }
}

function Install-CopilotCli {
    if (-not [string]::IsNullOrEmpty($Client) -and $Client -ne "copilot-cli") {
        return
    }

    if (-not (Test-CopilotCliInstalled)) {
        Write-Host "GitHub Copilot CLI not detected, skipping"
        return
    }

    # Copilot CLI requires type: local and tools: ["*"]
    $memvidEntry = @{
        type = "local"
        command = "cmd"
        args = @("/c", "npx", "-y", "@philiplaureano/memvid-mcp")
        env = @{
            MEMVID_DEFAULT_PATH = $MemoryPath
        }
        tools = @("*")
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] Would configure Copilot CLI: $COPILOT_CLI_CONFIG"
        return
    }

    if ($Uninstall) {
        Remove-MemvidConfig -ConfigFile $COPILOT_CLI_CONFIG
        Write-Success "Removed memvid from Copilot CLI"
    } else {
        # Ensure .copilot directory exists
        $copilotDir = Split-Path $COPILOT_CLI_CONFIG -Parent
        if (-not (Test-Path $copilotDir)) {
            New-Item -ItemType Directory -Path $copilotDir -Force | Out-Null
        }
        Merge-MemvidConfig -ConfigFile $COPILOT_CLI_CONFIG -MemvidEntry $memvidEntry
        Write-Success "Configured GitHub Copilot CLI ($COPILOT_CLI_CONFIG)"
    }
}

# Main
Write-Host "memvid-mcp Installer v$VERSION"
Write-Host ""

if ($Uninstall) {
    Write-Host "Uninstalling memvid-mcp..."
    Write-Host ""
    Install-ClaudeDesktop
    Install-ClaudeCode
    Install-CopilotCli
    Write-Host ""
    Write-Success "Uninstall complete"
    Write-Host ""
    Write-Host "Note: Memory file not deleted: $MemoryPath"
    exit 0
}

# Create memory file
New-MemoryFile

Write-Host ""
Write-Host "Configuring clients..."
Write-Host ""

Install-ClaudeDesktop
Install-ClaudeCode
Install-CopilotCli

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Warning "RESTART REQUIRED:"
Write-Host "   - Fully quit and reopen Claude Desktop"
Write-Host ""
Write-Host "VERIFY IT WORKED:" -ForegroundColor Yellow
Write-Host "   - Claude Desktop: Look for hammer icon in input box"
Write-Host "   - Claude Code: Run 'claude mcp list'"
Write-Host "   - Copilot CLI: Run '/mcp show'"
Write-Host ""
Write-Host "Memory file: $MemoryPath"
Write-Host "========================================================" -ForegroundColor Cyan
