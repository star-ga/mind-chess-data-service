#!/bin/bash
# Install script for Mind Chess Data Service
# Supports: AlmaLinux, RHEL, CentOS, Fedora, Ubuntu, Debian, Arch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Installation paths
INSTALL_DIR="/opt/chess-data-service"
CONFIG_DIR="/etc/chess-data-service"
DATA_DIR="/var/lib/chess-data"
LOG_DIR="/var/log/chess-data-service"
SERVICE_USER="chessdata"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_FAMILY=""

        case "$ID" in
            ubuntu|debian|linuxmint|pop)
                DISTRO_FAMILY="debian"
                ;;
            fedora|rhel|centos|almalinux|rocky)
                DISTRO_FAMILY="rhel"
                ;;
            arch|manjaro|endeavouros)
                DISTRO_FAMILY="arch"
                ;;
            opensuse*|sles)
                DISTRO_FAMILY="suse"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                ;;
        esac
    else
        DISTRO="unknown"
        DISTRO_FAMILY="unknown"
    fi

    log_info "Detected: $DISTRO ($DISTRO_FAMILY family)"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Run: sudo $0"
        exit 1
    fi
}

# Install dependencies based on distro
install_deps() {
    log_info "Installing dependencies..."

    case "$DISTRO_FAMILY" in
        debian)
            apt-get update
            apt-get install -y curl zstd
            ;;
        rhel)
            if command -v dnf &> /dev/null; then
                dnf install -y curl zstd
            else
                yum install -y curl zstd
            fi
            ;;
        arch)
            pacman -Sy --noconfirm curl zstd
            ;;
        suse)
            zypper install -y curl zstd
            ;;
        *)
            log_warn "Unknown distro, skipping dependency install"
            log_warn "Ensure curl and zstd are installed"
            ;;
    esac
}

# Create service user
create_user() {
    if id "$SERVICE_USER" &>/dev/null; then
        log_info "User $SERVICE_USER already exists"
    else
        log_info "Creating service user: $SERVICE_USER"
        useradd --system --no-create-home --shell /bin/false "$SERVICE_USER"
    fi
}

# Create directories
create_dirs() {
    log_info "Creating directories..."

    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR/book"
    mkdir -p "$DATA_DIR/tb8"
    mkdir -p "$DATA_DIR/nnue"
    mkdir -p "$LOG_DIR"

    chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
}

# Install binaries
install_binaries() {
    log_info "Installing binaries..."

    if [ ! -f "$PROJECT_DIR/bin/mind-chess-data-service" ]; then
        log_error "Binaries not found. Run ./build.sh first"
        exit 1
    fi

    cp "$PROJECT_DIR/bin/mind-chess-data-service" "$INSTALL_DIR/bin/"
    cp "$PROJECT_DIR/bin/import_pgn_to_book" "$INSTALL_DIR/bin/"
    cp "$PROJECT_DIR/bin/generate_nnue_from_pgn" "$INSTALL_DIR/bin/"
    cp "$PROJECT_DIR/bin/activate_version" "$INSTALL_DIR/bin/"

    chmod +x "$INSTALL_DIR/bin/"*

    # Create symlinks in /usr/local/bin
    ln -sf "$INSTALL_DIR/bin/mind-chess-data-service" /usr/local/bin/
    ln -sf "$INSTALL_DIR/bin/import_pgn_to_book" /usr/local/bin/
    ln -sf "$INSTALL_DIR/bin/generate_nnue_from_pgn" /usr/local/bin/
    ln -sf "$INSTALL_DIR/bin/activate_version" /usr/local/bin/
}

# Install config
install_config() {
    if [ -f "$CONFIG_DIR/config.toml" ]; then
        log_warn "Config exists, not overwriting: $CONFIG_DIR/config.toml"
    else
        log_info "Installing default config..."
        cp "$SCRIPT_DIR/config.toml" "$CONFIG_DIR/config.toml"
    fi
}

# Install systemd service
install_systemd() {
    log_info "Installing systemd service..."

    cat > /etc/systemd/system/chess-data-service.service << 'EOF'
[Unit]
Description=Mind Chess Data Service
After=network.target
Documentation=https://github.com/user/mind-chess-data-service

[Service]
Type=simple
User=chessdata
Group=chessdata
ExecStart=/opt/chess-data-service/bin/mind-chess-data-service --config /etc/chess-data-service/config.toml
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/chess-data-service/service.log
StandardError=append:/var/log/chess-data-service/error.log

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/chess-data /var/log/chess-data-service
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall..."

    case "$DISTRO_FAMILY" in
        rhel)
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --add-port=8787/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                log_info "Added port 8787 to firewalld"
            fi
            ;;
        debian)
            if command -v ufw &> /dev/null; then
                ufw allow 8787/tcp 2>/dev/null || true
                log_info "Added port 8787 to ufw"
            fi
            ;;
        arch)
            if command -v ufw &> /dev/null; then
                ufw allow 8787/tcp 2>/dev/null || true
            elif command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --add-port=8787/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
            fi
            ;;
    esac
}

# Print post-install instructions
print_instructions() {
    echo ""
    echo "========================================"
    echo "  Installation Complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Import opening book data:"
    echo "   curl -s https://database.lichess.org/standard/lichess_db_standard_rated_2024-01.pgn.zst | \\"
    echo "     zstdcat | import_pgn_to_book --stdin --output /var/lib/chess-data/book/v1/"
    echo "   activate_version book v1"
    echo ""
    echo "2. Start the service:"
    echo "   sudo systemctl start chess-data-service"
    echo "   sudo systemctl enable chess-data-service"
    echo ""
    echo "3. Test:"
    echo "   curl http://localhost:8787/health"
    echo ""
    echo "4. Configure Nikola engine:"
    echo "   setoption name BookUrl value http://<server-ip>:8787"
    echo "   setoption name UseRemoteBook value true"
    echo ""
    echo "Logs: /var/log/chess-data-service/"
    echo "Config: /etc/chess-data-service/config.toml"
    echo "Data: /var/lib/chess-data/"
    echo ""
}

# Main
main() {
    echo "========================================"
    echo "  Mind Chess Data Service Installer"
    echo "========================================"
    echo ""

    check_root
    detect_distro
    install_deps
    create_user
    create_dirs
    install_binaries
    install_config
    install_systemd
    configure_firewall
    print_instructions
}

main "$@"
