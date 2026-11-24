#!/bin/bash
# Build script for Mind Chess Data Service
# Uses Mind IR compiler (mic)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/bin"
SRC_DIR="${SCRIPT_DIR}/src"
TOOLS_DIR="${SCRIPT_DIR}/tools"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for Mind compiler
check_mic() {
    if ! command -v mic &> /dev/null; then
        log_error "Mind compiler (mic) not found in PATH"
        echo ""
        echo "Install Mind runtime:"
        echo "  curl -sSL https://mindlang.dev/install.sh | sh"
        echo ""
        echo "Or add to PATH:"
        echo "  export PATH=\$PATH:/path/to/mind/bin"
        exit 1
    fi
    log_info "Found mic: $(which mic)"
}

# Create build directory
setup_build() {
    mkdir -p "${BUILD_DIR}"
    log_info "Build directory: ${BUILD_DIR}"
}

# Compile main server
build_server() {
    log_info "Building mind-chess-data-service..."
    mic build \
        --release \
        --output "${BUILD_DIR}/mind-chess-data-service" \
        "${SRC_DIR}/main.mind"
    log_info "Built: ${BUILD_DIR}/mind-chess-data-service"
}

# Compile tools
build_tools() {
    log_info "Building tools..."

    mic build \
        --release \
        --output "${BUILD_DIR}/import_pgn_to_book" \
        "${TOOLS_DIR}/import_pgn_to_book.mind"
    log_info "Built: ${BUILD_DIR}/import_pgn_to_book"

    mic build \
        --release \
        --output "${BUILD_DIR}/generate_nnue_from_pgn" \
        "${TOOLS_DIR}/generate_nnue_from_pgn.mind"
    log_info "Built: ${BUILD_DIR}/generate_nnue_from_pgn"

    mic build \
        --release \
        --output "${BUILD_DIR}/activate_version" \
        "${TOOLS_DIR}/activate_version.mind"
    log_info "Built: ${BUILD_DIR}/activate_version"
}

# Run tests
run_tests() {
    log_info "Running tests..."
    mic test "${SRC_DIR}/core/zobrist.mind"
    log_info "Tests passed"
}

# Main
main() {
    echo "========================================"
    echo "  Mind Chess Data Service Builder"
    echo "========================================"
    echo ""

    check_mic
    setup_build

    case "${1:-all}" in
        server)
            build_server
            ;;
        tools)
            build_tools
            ;;
        test)
            run_tests
            ;;
        clean)
            log_info "Cleaning build directory..."
            rm -rf "${BUILD_DIR}"
            log_info "Clean complete"
            ;;
        all)
            build_server
            build_tools
            ;;
        *)
            echo "Usage: $0 [server|tools|test|clean|all]"
            exit 1
            ;;
    esac

    echo ""
    log_info "Build complete!"
    echo ""
    echo "Binaries in: ${BUILD_DIR}/"
    ls -la "${BUILD_DIR}/" 2>/dev/null || true
}

main "$@"
