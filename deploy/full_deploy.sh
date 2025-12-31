#!/bin/bash
# Full deployment script - Build + Install + Start
# One-command deployment for Mind Chess Data Service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    echo "Run: sudo $0"
    exit 1
fi

echo ""
echo "========================================"
echo "  Mind Chess Data Service - Full Deploy"
echo "========================================"
echo ""

# Step 1: Build
log_step "Step 1/4: Building from source..."
cd "$PROJECT_DIR"
if [ -f "./build.sh" ]; then
    chmod +x ./build.sh
    ./build.sh all
else
    log_error "build.sh not found"
    exit 1
fi

# Step 2: Install
log_step "Step 2/4: Installing..."
chmod +x "$SCRIPT_DIR/install.sh"
"$SCRIPT_DIR/install.sh"

# Step 3: Create initial data (empty book if none exists)
log_step "Step 3/4: Initializing data directories..."
DATA_DIR="/var/lib/chess-data"

# Create v1 directories if they don't exist
for dtype in book tb8 nnue; do
    mkdir -p "$DATA_DIR/$dtype/v1"

    # Create 'current' symlink if missing
    if [ ! -L "$DATA_DIR/$dtype/current" ]; then
        ln -sf "$DATA_DIR/$dtype/v1" "$DATA_DIR/$dtype/current"
        log_info "Created symlink: $DATA_DIR/$dtype/current -> v1"
    fi
done

# Create empty placeholder files if needed
if [ ! -f "$DATA_DIR/book/v1/book.idx" ]; then
    # Create minimal empty book
    log_info "Creating empty book placeholder..."
    # Header only: "BIDX" + version(1) + count(0)
    printf 'BIDX' > "$DATA_DIR/book/v1/book.idx"
    printf '\x01\x00\x00\x00' >> "$DATA_DIR/book/v1/book.idx"  # version 1
    printf '\x00\x00\x00\x00\x00\x00\x00\x00' >> "$DATA_DIR/book/v1/book.idx"  # count 0
    touch "$DATA_DIR/book/v1/book.dat"
fi

if [ ! -f "$DATA_DIR/nnue/v1/nnue.bin" ]; then
    log_info "Creating empty NNUE placeholder..."
    touch "$DATA_DIR/nnue/v1/nnue.bin"
fi

chown -R chessdata:chessdata "$DATA_DIR"

# Step 4: Start service
log_step "Step 4/4: Starting service..."
systemctl daemon-reload
systemctl enable chess-data-service
systemctl start chess-data-service

# Wait for startup
sleep 2

# Verify
log_info "Verifying service..."
if systemctl is-active --quiet chess-data-service; then
    log_info "Service is running"

    # Test health endpoint
    if curl -s http://localhost:8787/health | grep -q '"ok":true'; then
        log_info "Health check passed"
    else
        log_warn "Health check failed - service may still be starting"
    fi
else
    log_error "Service failed to start"
    echo ""
    echo "Check logs:"
    echo "  journalctl -u chess-data-service -n 50"
    echo "  cat /var/log/chess-data-service/error.log"
    exit 1
fi

echo ""
echo "========================================"
echo "  Deployment Complete!"
echo "========================================"
echo ""
echo "Service status:"
systemctl status chess-data-service --no-pager | head -10
echo ""
echo "Test with:"
echo "  curl http://localhost:8787/health"
echo ""
echo "To import opening book data:"
echo "  curl -s https://database.lichess.org/standard/lichess_db_standard_rated_2024-01.pgn.zst | \\"
echo "    zstdcat | import_pgn_to_book --stdin --output /var/lib/chess-data/book/v2/"
echo "  activate_version book v2"
echo "  curl -X POST http://localhost:8787/admin/reload"
echo ""
