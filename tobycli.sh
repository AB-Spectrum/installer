#!/bin/bash
# TobyCLI Single-Command Installer
# Usage: curl -sSL https://raw.githubusercontent.com/AB-Spectrum/installer/main/tobycli.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
REPO="AB-Spectrum/tobycli"
BINARY_NAME="toby"
INSTALL_DIR="${TOBY_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${TOBY_VERSION:-latest}"

# Print functions
print_status() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

# Check if command exists
need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Required command not found: $1"
        exit 1
    fi
}

# Check if gh CLI is available and authenticated
# Returns: 0=authenticated, 1=not installed, 2=not authenticated
check_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        return 1  # gh not installed
    fi

    if ! gh auth status >/dev/null 2>&1; then
        return 2  # gh installed but not authenticated
    fi

    return 0  # gh authenticated
}

# Check gh and provide helpful error message if needed
check_gh_with_message() {
    check_gh
    local status=$?

    case $status in
        1)
            print_warning "gh CLI not found"
            echo "Install gh CLI for easier authentication: https://cli.github.com/"
            echo "Or use GITHUB_TOKEN environment variable"
            return 1
            ;;
        2)
            print_warning "gh CLI not authenticated"
            echo "Run: gh auth login"
            echo "Or use GITHUB_TOKEN environment variable"
            return 1
            ;;
        0)
            return 0
            ;;
    esac
}

# Detect OS
detect_os() {
    OS=$(uname -s)
    case "$OS" in
        Darwin)
            OS="Darwin"
            ;;
        Linux)
            OS="Linux"
            ;;
        *)
            print_error "Unsupported OS: $OS"
            print_error "TobyCLI supports Linux and macOS only"
            exit 1
            ;;
    esac
}

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
}

# Get latest version
get_latest_version() {
    print_status "Fetching latest version..."

    # Try gh CLI first (best for private repos)
    check_gh
    local gh_status=$?

    if [ $gh_status -eq 0 ]; then
        print_status "Using gh CLI (authenticated)"
        VERSION=$(gh release view --repo "$REPO" --json tagName -q '.tagName' 2>/dev/null || true)
        if [ -n "$VERSION" ]; then
            return 0
        fi
    fi

    # Fall back to curl with token
    local api_url="https://api.github.com/repos/$REPO/releases/latest"
    local curl_args=(-sSf)

    if [ -n "$GITHUB_TOKEN" ]; then
        curl_args+=(-H "Authorization: token $GITHUB_TOKEN")
        print_status "Using GITHUB_TOKEN for private repo access"
    fi

    VERSION=$(curl "${curl_args[@]}" "$api_url" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 2>/dev/null || true)

    if [ -z "$VERSION" ]; then
        print_error "Failed to fetch latest version"
        print_error ""

        # Provide specific guidance based on gh status
        case $gh_status in
            1)
                print_error "Install gh CLI (recommended):"
                print_error "  https://cli.github.com/"
                print_error ""
                print_error "Or set GITHUB_TOKEN:"
                print_error "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
                ;;
            2)
                print_error "Authenticate with gh CLI (recommended):"
                print_error "  gh auth login"
                print_error ""
                print_error "Or set GITHUB_TOKEN:"
                print_error "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
                ;;
            *)
                print_error "For private repos:"
                print_error "  gh auth login"
                print_error "  OR"
                print_error "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
                ;;
        esac
        exit 1
    fi
}

# Download file
download() {
    local url="$1"
    local output="$2"
    local curl_args=(--proto '=https' --tlsv1.2 -sSfL -o "$output")

    if [ -n "$GITHUB_TOKEN" ]; then
        curl_args+=(-H "Authorization: token $GITHUB_TOKEN")
    fi

    if ! curl "${curl_args[@]}" "$url"; then
        return 1
    fi
    return 0
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local checksums_url="$2"
    local filename
    filename=$(basename "$file")

    print_status "Verifying checksum..."

    local checksums_file="${file}.checksums"
    if ! download "$checksums_url" "$checksums_file" 2>/dev/null; then
        print_warning "Checksum file not available, skipping verification"
        return 0
    fi

    if [ -f "$checksums_file" ]; then
        local hash_cmd=""
        if command -v shasum >/dev/null 2>&1; then
            hash_cmd="shasum -a 256"
        elif command -v sha256sum >/dev/null 2>&1; then
            hash_cmd="sha256sum"
        else
            print_warning "sha256sum/shasum not available, skipping verification"
            rm -f "$checksums_file"
            return 0
        fi

        local expected
        expected=$(grep "$filename" "$checksums_file" | awk '{print $1}')
        if [ -z "$expected" ]; then
            print_warning "Checksum not found for $filename, skipping verification"
            rm -f "$checksums_file"
            return 0
        fi

        local actual
        actual=$($hash_cmd "$file" | awk '{print $1}')

        if [ "$expected" != "$actual" ]; then
            print_error "Checksum verification failed!"
            echo "Expected: $expected" >&2
            echo "Actual: $actual" >&2
            rm -f "$checksums_file"
            exit 1
        fi

        print_status "Checksum verified ✓"
        rm -f "$checksums_file"
    fi
}

# Install binary
install_binary() {
    local os="$1"
    local arch="$2"
    local version="$3"

    local archive_name="tobycli_${os}_${arch}.tar.gz"
    local download_url="https://github.com/$REPO/releases/download/$version/$archive_name"
    local checksums_url="https://github.com/$REPO/releases/download/$version/checksums.txt"

    print_status "Downloading TobyCLI $version for $os/$arch..."

    # Create temp directory
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    local archive_path="$tmp_dir/$archive_name"

    # Try gh CLI first (best for private repos)
    check_gh
    local gh_status=$?

    if [ $gh_status -eq 0 ]; then
        print_status "Using gh CLI for download"
        if gh release download "$version" --repo "$REPO" --pattern "$archive_name" --dir "$tmp_dir" 2>/dev/null; then
            # Also download checksums for verification
            gh release download "$version" --repo "$REPO" --pattern "checksums.txt" --dir "$tmp_dir" 2>/dev/null || true

            # Verify checksum if available
            if [ -f "$tmp_dir/checksums.txt" ]; then
                local checksums_file="$tmp_dir/checksums.txt"
                local filename
                filename=$(basename "$archive_path")
                local hash_cmd=""

                if command -v shasum >/dev/null 2>&1; then
                    hash_cmd="shasum -a 256"
                elif command -v sha256sum >/dev/null 2>&1; then
                    hash_cmd="sha256sum"
                fi

                if [ -n "$hash_cmd" ]; then
                    local expected
                    expected=$(grep "$filename" "$checksums_file" | awk '{print $1}')
                    if [ -n "$expected" ]; then
                        local actual
                        actual=$($hash_cmd "$archive_path" | awk '{print $1}')
                        if [ "$expected" = "$actual" ]; then
                            print_status "Checksum verified ✓"
                        else
                            print_error "Checksum verification failed!"
                            echo "Expected: $expected" >&2
                            echo "Actual: $actual" >&2
                            exit 1
                        fi
                    fi
                fi
            fi
        else
            print_warning "Failed to download using gh CLI, falling back to curl..."
        fi
    elif [ $gh_status -eq 1 ]; then
        print_warning "gh CLI not installed, using curl..."
    elif [ $gh_status -eq 2 ]; then
        print_warning "gh CLI not authenticated, using curl..."
    fi

    # Fall back to curl if gh failed or not available
    if [ ! -f "$archive_path" ]; then
        if ! download "$download_url" "$archive_path"; then
            print_error "Failed to download: $download_url"
            print_error ""

            # Provide specific guidance based on gh status
            case $gh_status in
                1)
                    print_error "Install gh CLI (recommended):"
                    print_error "  https://cli.github.com/"
                    print_error "  gh auth login"
                    print_error ""
                    print_error "Or set GITHUB_TOKEN:"
                    print_error "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
                    ;;
                2)
                    print_error "Authenticate with gh CLI (recommended):"
                    print_error "  gh auth login"
                    print_error ""
                    print_error "Or set GITHUB_TOKEN:"
                    print_error "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
                    ;;
                *)
                    print_error "For private repos:"
                    print_error "  gh auth login"
                    print_error "  OR"
                    print_error "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
                    ;;
            esac
            exit 1
        fi
        # Verify checksum
        verify_checksum "$archive_path" "$checksums_url"
    fi

    # Extract archive
    print_status "Extracting archive..."
    cd "$tmp_dir"

    if ! tar -xzf "$archive_path"; then
        print_error "Failed to extract archive"
        exit 1
    fi

    # Find binary
    local binary_path
    binary_path=$(find . -type f -name "$BINARY_NAME" | head -n 1)

    if [ -z "$binary_path" ]; then
        print_error "Binary '$BINARY_NAME' not found in archive"
        ls -la
        exit 1
    fi

    # Make executable
    chmod +x "$binary_path"

    # Create install directory if needed
    mkdir -p "$INSTALL_DIR"

    # Install binary
    local final_path="$INSTALL_DIR/$BINARY_NAME"
    mv "$binary_path" "$final_path"

    print_status "Installed to: $final_path"
}

# Update PATH in shell config
update_path() {
    if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
        return 0
    fi

    local updated=false
    local shell_files=()

    # Detect shell and config files
    if [ -f "$HOME/.zshrc" ]; then
        shell_files+=("$HOME/.zshrc")
    fi
    if [ -f "$HOME/.bashrc" ]; then
        shell_files+=("$HOME/.bashrc")
    fi
    if [ -f "$HOME/.bash_profile" ]; then
        shell_files+=("$HOME/.bash_profile")
    fi

    # Update shell config files
    for shell_file in "${shell_files[@]}"; do
        if ! grep -qF "# Added by TobyCLI installer" "$shell_file" 2>/dev/null; then
            {
                echo ""
                echo "# Added by TobyCLI installer"
                echo "export PATH=\"\$PATH:$INSTALL_DIR\""
            } >> "$shell_file"
            print_status "Updated PATH in $(basename "$shell_file")"
            updated=true
        fi
    done

    if [ "$updated" = true ]; then
        echo ""
        print_warning "PATH updated! Reload your shell:"
        if [ -f "$HOME/.zshrc" ]; then
            echo "  source ~/.zshrc"
        elif [ -f "$HOME/.bashrc" ]; then
            echo "  source ~/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            echo "  source ~/.bash_profile"
        fi
        echo "  Or restart your terminal"
        echo ""
    fi
}

# Main installation function (wrapped to prevent incomplete execution)
main() {
    printf "${GREEN}TobyCLI Installer${NC}\n"
    echo "=================="
    echo ""

    # Check required commands
    need_cmd curl
    need_cmd tar
    need_cmd grep
    need_cmd awk

    # Detect platform
    detect_os
    detect_arch

    echo "OS: $OS"
    echo "Architecture: $ARCH"
    echo "Install Directory: $INSTALL_DIR"
    echo ""

    # Get version
    if [ "$VERSION" = "latest" ]; then
        get_latest_version
    else
        # Ensure version starts with v
        if [[ ! $VERSION =~ ^v ]]; then
            VERSION="v$VERSION"
        fi
    fi

    print_status "Installing TobyCLI $VERSION"
    echo ""

    # Install binary
    install_binary "$OS" "$ARCH" "$VERSION"

    # Update PATH
    update_path

    echo ""
    printf "${GREEN}Installation complete! ✓${NC}\n"
    echo ""
    printf "${YELLOW}Get started:${NC}\n"
    echo "  $BINARY_NAME --help"
    echo "  $BINARY_NAME init"
    echo "  $BINARY_NAME auth login"
    echo ""

    # Show version
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        printf "${YELLOW}Installed version:${NC}\n"
        "$BINARY_NAME" --version 2>/dev/null || echo "  $VERSION"
    else
        printf "${YELLOW}Installed version:${NC} %s\n" "$VERSION"
        echo ""
        print_warning "Reload your shell to use '$BINARY_NAME' command"
    fi
}

# Execute main function on last line (prevents incomplete execution if connection drops)
main "$@"
