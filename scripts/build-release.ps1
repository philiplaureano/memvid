#Requires -Version 5.1
<#
.SYNOPSIS
    memvid Release Builder (Windows)
.DESCRIPTION
    Builds Rust binary + MCP server into a distributable zip file
.EXAMPLE
    .\build-release.ps1
#>

$ErrorActionPreference = "Stop"
$VERSION = "1.0.0"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Detect architecture
$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$Platform = "windows-$Arch"
$DistName = "memvid-$Platform"
$DistDir = Join-Path $RootDir "dist\$DistName"

Write-Host "Building memvid release for $Platform..."
Write-Host ""

# Clean previous build
if (Test-Path $DistDir) {
    Remove-Item -Recurse -Force $DistDir
}
New-Item -ItemType Directory -Path "$DistDir\bin" -Force | Out-Null
New-Item -ItemType Directory -Path "$DistDir\mcp" -Force | Out-Null

# Build Rust CLI binary
Write-Host "Building Rust CLI binary..."
Push-Location "$RootDir\cli"
try {
    & cargo build --release
    if ($LASTEXITCODE -ne 0) {
        throw "Cargo build failed"
    }
} finally {
    Pop-Location
}

# Copy binary
Write-Host "Copying binary..."
Copy-Item "$RootDir\cli\target\release\memvid.exe" "$DistDir\bin\"

# Build MCP server with dependencies
Write-Host "Building MCP server..."
Push-Location "$RootDir\mcp"
try {
    & npm ci --production
    if ($LASTEXITCODE -ne 0) {
        throw "npm ci failed"
    }
} finally {
    Pop-Location
}

# Copy MCP server with node_modules
Write-Host "Copying MCP server..."
Copy-Item -Recurse "$RootDir\mcp\dist" "$DistDir\mcp\"
Copy-Item -Recurse "$RootDir\mcp\node_modules" "$DistDir\mcp\"
Copy-Item "$RootDir\mcp\package.json" "$DistDir\mcp\"
if (Test-Path "$RootDir\mcp\README.md") { Copy-Item "$RootDir\mcp\README.md" "$DistDir\mcp\" }
if (Test-Path "$RootDir\mcp\QUICKSTART.md") { Copy-Item "$RootDir\mcp\QUICKSTART.md" "$DistDir\mcp\" }
if (Test-Path "$RootDir\mcp\MEMVID_INSTRUCTIONS.md") { Copy-Item "$RootDir\mcp\MEMVID_INSTRUCTIONS.md" "$DistDir\mcp\" }

# Create bundled install script
$InstallScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    memvid Bundled Installer
.DESCRIPTION
    Installs pre-built binary + MCP server + configures MCP clients
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:LOCALAPPDATA "memvid"
$BinDir = Join-Path $InstallDir "bin"
$McpDir = Join-Path $InstallDir "mcp"
$MemoryPath = Join-Path $HOME ".memvid\memory.mv2"

Write-Host "memvid Installer"
Write-Host ""

# Create install directories
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}
if (-not (Test-Path $McpDir)) {
    New-Item -ItemType Directory -Path $McpDir -Force | Out-Null
}

# Copy binary
Write-Host "Installing memvid binary to $BinDir..."
Copy-Item "$ScriptDir\bin\memvid.exe" "$BinDir\" -Force

# Copy MCP server
Write-Host "Installing MCP server to $McpDir..."
if (Test-Path "$McpDir\dist") { Remove-Item -Recurse -Force "$McpDir\dist" }
if (Test-Path "$McpDir\node_modules") { Remove-Item -Recurse -Force "$McpDir\node_modules" }
Copy-Item -Recurse "$ScriptDir\mcp\dist" "$McpDir\"
Copy-Item -Recurse "$ScriptDir\mcp\node_modules" "$McpDir\"
Copy-Item "$ScriptDir\mcp\package.json" "$McpDir\" -Force

# Check if bin dir is in PATH
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    Write-Host ""
    Write-Host "Adding $BinDir to user PATH..."
    $NewPath = "$BinDir;$UserPath"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    $env:Path = "$BinDir;$env:Path"
    Write-Host "  Added to PATH (restart terminal to take effect)"
}

# Create memory directory and file
$MemoryDir = Split-Path $MemoryPath -Parent
if (-not (Test-Path $MemoryDir)) {
    New-Item -ItemType Directory -Path $MemoryDir -Force | Out-Null
}
if (-not (Test-Path $MemoryPath)) {
    New-Item -ItemType File -Path $MemoryPath -Force | Out-Null
    Write-Host "Created memory file: $MemoryPath"
}

# MCP server entry point
$McpEntryPoint = Join-Path $McpDir "dist\index.js"

# Config paths
$ClaudeDesktopConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$CopilotCliConfig = Join-Path $HOME ".copilot\mcp-config.json"

function Merge-MemvidConfig {
    param([string]$ConfigFile, [hashtable]$MemvidEntry)

    $config = @{}
    if (Test-Path $ConfigFile) {
        try {
            $content = Get-Content $ConfigFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $config = $content | ConvertFrom-Json -AsHashtable
            }
        } catch { $config = @{} }
    }

    if (-not $config.ContainsKey("mcpServers")) {
        $config["mcpServers"] = @{}
    }

    $config["mcpServers"]["memvid"] = $MemvidEntry

    $configDir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8
}

# Configure Claude Desktop
$ClaudeDesktopDir = Split-Path $ClaudeDesktopConfig -Parent
if ((Test-Path $ClaudeDesktopDir) -or (Test-Path $ClaudeDesktopConfig)) {
    Write-Host "Configuring Claude Desktop..."
    $memvidEntry = @{
        command = "node"
        args = @($McpEntryPoint)
        env = @{
            MEMVID_DEFAULT_PATH = $MemoryPath
            MEMVID_CLI_PATH = "$BinDir\memvid.exe"
        }
    }
    Merge-MemvidConfig -ConfigFile $ClaudeDesktopConfig -MemvidEntry $memvidEntry
    Write-Host "  Configured: $ClaudeDesktopConfig"
}

# Configure Claude Code
$claudeCmd = Get-Command "claude" -ErrorAction SilentlyContinue
if ($null -ne $claudeCmd) {
    Write-Host "Configuring Claude Code..."
    try { & claude mcp remove memvid 2>$null } catch { }

    $mcpJson = @{
        command = "node"
        args = @($McpEntryPoint)
        env = @{
            MEMVID_DEFAULT_PATH = $MemoryPath
            MEMVID_CLI_PATH = "$BinDir\memvid.exe"
        }
    } | ConvertTo-Json -Compress

    & claude mcp add-json memvid $mcpJson --scope user
    Write-Host "  Configured via claude mcp add-json"
}

# Configure Copilot CLI
$CopilotDir = Join-Path $HOME ".copilot"
$copilotCmd = Get-Command "copilot" -ErrorAction SilentlyContinue
if ((Test-Path $CopilotDir) -or ($null -ne $copilotCmd)) {
    Write-Host "Configuring GitHub Copilot CLI..."
    if (-not (Test-Path $CopilotDir)) {
        New-Item -ItemType Directory -Path $CopilotDir -Force | Out-Null
    }
    $memvidEntry = @{
        type = "local"
        command = "node"
        args = @($McpEntryPoint)
        env = @{
            MEMVID_DEFAULT_PATH = $MemoryPath
            MEMVID_CLI_PATH = "$BinDir\memvid.exe"
        }
        tools = @("*")
    }
    Merge-MemvidConfig -ConfigFile $CopilotCliConfig -MemvidEntry $memvidEntry
    Write-Host "  Configured: $CopilotCliConfig"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "INSTALLED TO:" -ForegroundColor Yellow
Write-Host "  Binary: $BinDir\memvid.exe"
Write-Host "  MCP Server: $McpDir"
Write-Host ""
Write-Host "RESTART REQUIRED:" -ForegroundColor Yellow
Write-Host "  Fully quit and reopen Claude Desktop"
Write-Host "  Restart your terminal for PATH changes"
Write-Host ""
Write-Host "VERIFY:" -ForegroundColor Yellow
Write-Host "  memvid --version"
Write-Host "  Claude Desktop: Look for hammer icon"
Write-Host "  Claude Code: claude mcp list"
Write-Host ""
Write-Host "Memory file: $MemoryPath"
Write-Host "========================================================" -ForegroundColor Cyan
'@

Set-Content -Path "$DistDir\install.ps1" -Value $InstallScript -Encoding UTF8

# Create zip
Write-Host ""
Write-Host "Creating zip archive..."
$ZipPath = Join-Path $RootDir "dist\$DistName.zip"
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Compress-Archive -Path $DistDir -DestinationPath $ZipPath

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Build complete!"
Write-Host ""
Write-Host "Output: dist\$DistName.zip"
Write-Host ""
Write-Host "To install on target machine:"
Write-Host "  1. Extract zip"
Write-Host "  2. Run install.ps1 as Administrator"
Write-Host "========================================================" -ForegroundColor Cyan
