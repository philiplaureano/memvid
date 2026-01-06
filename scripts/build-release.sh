#!/usr/bin/env bash
set -e

# memvid Release Builder (macOS/Linux)
# Builds Rust binary + MCP server into a distributable tarball

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Detect platform
detect_platform() {
    local os arch
    case "$(uname -s)" in
        Darwin*) os="macos" ;;
        Linux*) os="linux" ;;
        *) echo "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    echo "${os}-${arch}"
}

PLATFORM=$(detect_platform)
DIST_NAME="memvid-${PLATFORM}"
DIST_DIR="${ROOT_DIR}/dist/${DIST_NAME}"

echo "Building memvid release for ${PLATFORM}..."
echo ""

# Clean previous build
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/bin"
mkdir -p "${DIST_DIR}/mcp"

# Build Rust CLI binary
echo "Building Rust CLI binary..."
cd "${ROOT_DIR}/cli"
cargo build --release

# Copy binary
echo "Copying binary..."
cp "${ROOT_DIR}/cli/target/release/memvid" "${DIST_DIR}/bin/"
chmod +x "${DIST_DIR}/bin/memvid"

# Copy MCP server
echo "Copying MCP server..."
cp -r "${ROOT_DIR}/mcp/dist" "${DIST_DIR}/mcp/"
cp "${ROOT_DIR}/mcp/package.json" "${DIST_DIR}/mcp/"
cp "${ROOT_DIR}/mcp/README.md" "${DIST_DIR}/mcp/" 2>/dev/null || true
cp "${ROOT_DIR}/mcp/QUICKSTART.md" "${DIST_DIR}/mcp/" 2>/dev/null || true
cp "${ROOT_DIR}/mcp/MEMVID_INSTRUCTIONS.md" "${DIST_DIR}/mcp/" 2>/dev/null || true

# Create bundled install script
cat > "${DIST_DIR}/install.sh" << 'INSTALL_EOF'
#!/usr/bin/env bash
set -e

# memvid Bundled Installer
# Installs pre-built binary + configures MCP servers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
MEMORY_PATH="$HOME/.memvid/memory.mv2"

echo "memvid Installer"
echo ""

# Create bin directory
mkdir -p "$BIN_DIR"

# Copy binary
echo "Installing memvid binary to $BIN_DIR..."
cp "$SCRIPT_DIR/bin/memvid" "$BIN_DIR/"
chmod +x "$BIN_DIR/memvid"

# Check if bin dir is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "NOTE: $BIN_DIR is not in your PATH."
    echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# Create memory directory
mkdir -p "$(dirname "$MEMORY_PATH")"
if [[ ! -f "$MEMORY_PATH" ]]; then
    touch "$MEMORY_PATH"
    echo "Created memory file: $MEMORY_PATH"
fi

# Detect OS for config paths
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

OS=$(detect_os)

# Claude Desktop config path
if [[ "$OS" == "macos" ]]; then
    CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
else
    CLAUDE_DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"
fi

COPILOT_CLI_CONFIG="$HOME/.copilot/mcp-config.json"

# JSON merge using Python
merge_memvid_config() {
    local config_file="$1"
    local memvid_entry="$2"

    python3 << EOF
import json
import os

config_file = "$config_file"
memvid_entry = json.loads('''$memvid_entry''')

if os.path.exists(config_file):
    with open(config_file, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            config = {}
else:
    config = {}

if 'mcpServers' not in config:
    config['mcpServers'] = {}

config['mcpServers']['memvid'] = memvid_entry

os.makedirs(os.path.dirname(config_file), exist_ok=True)
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
EOF
}

# Configure Claude Desktop
if [[ -d "$(dirname "$CLAUDE_DESKTOP_CONFIG")" ]] || [[ -f "$CLAUDE_DESKTOP_CONFIG" ]]; then
    echo "Configuring Claude Desktop..."
    memvid_entry=$(cat << EOF
{
    "command": "npx",
    "args": ["-y", "@philiplaureano/memvid-mcp"],
    "env": {
        "MEMVID_DEFAULT_PATH": "$MEMORY_PATH",
        "MEMVID_CLI_PATH": "$BIN_DIR/memvid"
    }
}
EOF
)
    merge_memvid_config "$CLAUDE_DESKTOP_CONFIG" "$memvid_entry"
    echo "  Configured: $CLAUDE_DESKTOP_CONFIG"
fi

# Configure Claude Code
if command -v claude &> /dev/null; then
    echo "Configuring Claude Code..."
    claude mcp remove memvid 2>/dev/null || true
    claude mcp add-json memvid "{\"command\":\"npx\",\"args\":[\"-y\",\"@philiplaureano/memvid-mcp\"],\"env\":{\"MEMVID_DEFAULT_PATH\":\"$MEMORY_PATH\",\"MEMVID_CLI_PATH\":\"$BIN_DIR/memvid\"}}" --scope user
    echo "  Configured via claude mcp add-json"
fi

# Configure Copilot CLI
if [[ -d "$HOME/.copilot" ]] || command -v copilot &> /dev/null; then
    echo "Configuring GitHub Copilot CLI..."
    mkdir -p "$HOME/.copilot"
    memvid_entry=$(cat << EOF
{
    "type": "local",
    "command": "npx",
    "args": ["-y", "@philiplaureano/memvid-mcp"],
    "env": {
        "MEMVID_DEFAULT_PATH": "$MEMORY_PATH",
        "MEMVID_CLI_PATH": "$BIN_DIR/memvid"
    },
    "tools": ["*"]
}
EOF
)
    merge_memvid_config "$COPILOT_CLI_CONFIG" "$memvid_entry"
    echo "  Configured: $COPILOT_CLI_CONFIG"
fi

echo ""
echo "========================================================"
echo "RESTART REQUIRED:"
echo "  Fully quit and reopen Claude Desktop"
echo ""
echo "VERIFY:"
echo "  memvid --version"
echo "  Claude Desktop: Look for hammer icon"
echo "  Claude Code: claude mcp list"
echo ""
echo "Memory file: $MEMORY_PATH"
echo "========================================================"
INSTALL_EOF

chmod +x "${DIST_DIR}/install.sh"

# Create tarball
echo ""
echo "Creating tarball..."
cd "${ROOT_DIR}/dist"
tar -czvf "${DIST_NAME}.tar.gz" "${DIST_NAME}"

echo ""
echo "========================================================"
echo "Build complete!"
echo ""
echo "Output: dist/${DIST_NAME}.tar.gz"
echo ""
echo "To install on target machine:"
echo "  tar xzf ${DIST_NAME}.tar.gz"
echo "  cd ${DIST_NAME}"
echo "  ./install.sh"
echo "========================================================"
