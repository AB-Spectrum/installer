# AB-Spectrum Installers

Single-command installers for AB-Spectrum tools.

## TobyCLI

### Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/AB-Spectrum/installer/main/tobycli.sh | bash
```

### Private Repository Access

For private repositories, set your GitHub token before running the installer:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
curl -sSL https://raw.githubusercontent.com/AB-Spectrum/installer/main/tobycli.sh | bash
```

To create a token:
1. Go to https://github.com/settings/tokens
2. Generate new token (classic)
3. Select `repo` scope for private repository access
4. Copy the token and export it as shown above

### Custom Installation

```bash
# Install specific version
export TOBY_VERSION=v1.6.1
curl -sSL https://raw.githubusercontent.com/AB-Spectrum/installer/main/tobycli.sh | bash

# Install to custom directory
export TOBY_INSTALL_DIR=$HOME/bin
curl -sSL https://raw.githubusercontent.com/AB-Spectrum/installer/main/tobycli.sh | bash
```

### Supported Platforms

- **macOS**: x86_64 (Intel), arm64 (Apple Silicon)
- **Linux**: x86_64, arm64

### Security Features

- HTTPS-only downloads with TLS 1.2+
- SHA-256 checksum verification
- Wrapped script execution (prevents incomplete execution)
- GitHub token support for private repositories

### Post-Installation

After installation, reload your shell:

```bash
# For zsh
source ~/.zshrc

# For bash
source ~/.bashrc
# or
source ~/.bash_profile
```

Then verify installation:

```bash
toby --version
toby --help
```

## Other Tools

More installers coming soon...
