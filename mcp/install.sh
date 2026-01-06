#!/usr/bin/env bash
set -e

# memvid-mcp Installer
# Configures memvid memory for Claude Desktop, Claude Code, and GitHub Copilot CLI

VERSION="1.0.0"
DEFAULT_MEMORY_PATH="$HOME/.memvid/memory.mv2"
MEMORY_PATH=""
DRY_RUN=false
UNINSTALL=false
TARGET_CLIENT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

usage() {
    cat << EOF
memvid-mcp Installer v$VERSION

Usage: ./install.sh [OPTIONS]

Options:
    --memory-path <path>    Custom memory file location (default: ~/.memvid/memory.mv2)
    --client <name>         Configure only one client (claude-desktop, claude-code, copilot-cli)
    --dry-run               Show what would happen without making changes
    --uninstall             Remove memvid from all clients
    --help                  Show this help message

Examples:
    ./install.sh                                    # Install with defaults
    ./install.sh --memory-path /data/memory.mv2    # Custom memory path
    ./install.sh --client claude-code              # Only configure Claude Code
    ./install.sh --uninstall                       # Remove memvid config
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --memory-path)
            MEMORY_PATH="$2"
            shift 2
            ;;
        --client)
            TARGET_CLIENT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Set memory path to default if not specified
if [[ -z "$MEMORY_PATH" ]]; then
    MEMORY_PATH="$DEFAULT_MEMORY_PATH"
fi

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

OS=$(detect_os)

# Config paths
get_claude_desktop_config_path() {
    if [[ "$OS" == "macos" ]]; then
        echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    else
        echo "$HOME/.config/Claude/claude_desktop_config.json"
    fi
}

CLAUDE_DESKTOP_CONFIG=$(get_claude_desktop_config_path)
COPILOT_CLI_CONFIG="$HOME/.copilot/mcp-config.json"

# Check if client is installed
is_claude_desktop_installed() {
    [[ -d "$(dirname "$CLAUDE_DESKTOP_CONFIG")" ]] || [[ -f "$CLAUDE_DESKTOP_CONFIG" ]]
}

is_claude_code_installed() {
    command -v claude &> /dev/null
}

is_copilot_cli_installed() {
    [[ -d "$HOME/.copilot" ]] || command -v copilot &> /dev/null
}

# JSON manipulation using Python (available on macOS/Linux)
merge_memvid_config() {
    local config_file="$1"
    local memvid_entry="$2"

    python3 << EOF
import json
import os

config_file = "$config_file"
memvid_entry = json.loads('''$memvid_entry''')

# Read existing config or create new
if os.path.exists(config_file):
    with open(config_file, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            config = {}
else:
    config = {}

# Ensure mcpServers exists
if 'mcpServers' not in config:
    config['mcpServers'] = {}

# Add or update memvid
config['mcpServers']['memvid'] = memvid_entry

# Write back
os.makedirs(os.path.dirname(config_file), exist_ok=True)
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
EOF
}

remove_memvid_config() {
    local config_file="$1"

    python3 << EOF
import json
import os

config_file = "$config_file"

if not os.path.exists(config_file):
    exit(0)

with open(config_file, 'r') as f:
    try:
        config = json.load(f)
    except json.JSONDecodeError:
        exit(0)

if 'mcpServers' in config and 'memvid' in config['mcpServers']:
    del config['mcpServers']['memvid']
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
EOF
}

# Create memory directory and file
create_memory_file() {
    local memory_dir=$(dirname "$MEMORY_PATH")

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would create: $MEMORY_PATH"
        return
    fi

    if [[ ! -d "$memory_dir" ]]; then
        mkdir -p "$memory_dir"
    fi

    if [[ ! -f "$MEMORY_PATH" ]]; then
        # Create empty mv2 file (memvid will initialize it on first use)
        touch "$MEMORY_PATH"
        print_success "Created $MEMORY_PATH"
    else
        print_success "Memory file exists: $MEMORY_PATH"
    fi
}

# Configure Claude Desktop
configure_claude_desktop() {
    if [[ -n "$TARGET_CLIENT" && "$TARGET_CLIENT" != "claude-desktop" ]]; then
        return
    fi

    if ! is_claude_desktop_installed; then
        echo "Claude Desktop not detected, skipping"
        return
    fi

    local memvid_entry=$(cat << EOF
{
    "command": "npx",
    "args": ["-y", "@philiplaureano/memvid-mcp"],
    "env": {
        "MEMVID_DEFAULT_PATH": "$MEMORY_PATH"
    }
}
EOF
)

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would configure Claude Desktop: $CLAUDE_DESKTOP_CONFIG"
        return
    fi

    if [[ "$UNINSTALL" == "true" ]]; then
        remove_memvid_config "$CLAUDE_DESKTOP_CONFIG"
        print_success "Removed memvid from Claude Desktop"
    else
        merge_memvid_config "$CLAUDE_DESKTOP_CONFIG" "$memvid_entry"
        print_success "Configured Claude Desktop ($CLAUDE_DESKTOP_CONFIG)"
    fi
}

# Configure Claude Code
configure_claude_code() {
    if [[ -n "$TARGET_CLIENT" && "$TARGET_CLIENT" != "claude-code" ]]; then
        return
    fi

    if ! is_claude_code_installed; then
        echo "Claude Code not detected, skipping"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would configure Claude Code via: claude mcp add-json"
        return
    fi

    if [[ "$UNINSTALL" == "true" ]]; then
        claude mcp remove memvid 2>/dev/null || true
        print_success "Removed memvid from Claude Code"
    else
        # Remove existing first (if any)
        claude mcp remove memvid 2>/dev/null || true

        # Add memvid
        claude mcp add-json memvid "{\"command\":\"npx\",\"args\":[\"-y\",\"@philiplaureano/memvid-mcp\"],\"env\":{\"MEMVID_DEFAULT_PATH\":\"$MEMORY_PATH\"}}" --scope user
        print_success "Configured Claude Code"
    fi
}

# Configure GitHub Copilot CLI
configure_copilot_cli() {
    if [[ -n "$TARGET_CLIENT" && "$TARGET_CLIENT" != "copilot-cli" ]]; then
        return
    fi

    if ! is_copilot_cli_installed; then
        echo "GitHub Copilot CLI not detected, skipping"
        return
    fi

    local memvid_entry=$(cat << EOF
{
    "type": "local",
    "command": "npx",
    "args": ["-y", "@philiplaureano/memvid-mcp"],
    "env": {
        "MEMVID_DEFAULT_PATH": "$MEMORY_PATH"
    },
    "tools": ["*"]
}
EOF
)

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would configure Copilot CLI: $COPILOT_CLI_CONFIG"
        return
    fi

    if [[ "$UNINSTALL" == "true" ]]; then
        remove_memvid_config "$COPILOT_CLI_CONFIG"
        print_success "Removed memvid from Copilot CLI"
    else
        # Ensure .copilot directory exists
        mkdir -p "$HOME/.copilot"
        merge_memvid_config "$COPILOT_CLI_CONFIG" "$memvid_entry"
        print_success "Configured GitHub Copilot CLI ($COPILOT_CLI_CONFIG)"
    fi
}

# Main
main() {
    echo "memvid-mcp Installer v$VERSION"
    echo ""

    if [[ "$UNINSTALL" == "true" ]]; then
        echo "Uninstalling memvid-mcp..."
        echo ""
        configure_claude_desktop
        configure_claude_code
        configure_copilot_cli
        echo ""
        print_success "Uninstall complete"
        echo ""
        echo "Note: Memory file not deleted: $MEMORY_PATH"
        exit 0
    fi

    # Create memory file
    create_memory_file

    echo ""
    echo "Configuring clients..."
    echo ""

    configure_claude_desktop
    configure_claude_code
    configure_copilot_cli

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "RESTART REQUIRED:"
    echo "   • Fully quit and reopen Claude Desktop"
    echo ""
    echo "VERIFY IT WORKED:"
    echo "   • Claude Desktop: Look for 🔨 icon in input box"
    echo "   • Claude Code: Run 'claude mcp list'"
    echo "   • Copilot CLI: Run '/mcp show'"
    echo ""
    echo "Memory file: $MEMORY_PATH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main
