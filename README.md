# Mind Chess Data Service

LAN chess data service in pure Mind. Opening book + TB8 + NNUE via HTTP.

## Quick Start

### One-Command Deploy (All Distros)
```bash
git clone <repo>
cd mind-chess-data-service
sudo ./deploy/full_deploy.sh
curl http://localhost:8787/health
```

## Deployment by Distribution

### Ubuntu / Debian / Linux Mint

```bash
# Prerequisites
sudo apt update
sudo apt install -y git curl zstd build-essential

# Install Mind runtime
curl -sSL https://mindlang.dev/install.sh | sh
export PATH="$PATH:$HOME/.mind/bin"

# Clone and build
git clone <repo>
cd mind-chess-data-service
./build.sh

# Deploy
sudo ./deploy/install.sh
sudo systemctl start chess-data-service
sudo systemctl enable chess-data-service

# Test
curl http://localhost:8787/health
```

### AlmaLinux / RHEL / CentOS / Rocky Linux

```bash
# Prerequisites
sudo dnf install -y git curl zstd gcc

# Install Mind runtime
curl -sSL https://mindlang.dev/install.sh | sh
export PATH="$PATH:$HOME/.mind/bin"

# Clone and build
git clone <repo>
cd mind-chess-data-service
./build.sh

# Deploy
sudo ./deploy/install.sh
sudo systemctl start chess-data-service
sudo systemctl enable chess-data-service

# Open firewall
sudo firewall-cmd --permanent --add-port=8787/tcp
sudo firewall-cmd --reload

# Test
curl http://localhost:8787/health
```

### Fedora

```bash
# Prerequisites
sudo dnf install -y git curl zstd gcc

# Install Mind runtime
curl -sSL https://mindlang.dev/install.sh | sh
export PATH="$PATH:$HOME/.mind/bin"

# Clone and build
git clone <repo>
cd mind-chess-data-service
./build.sh

# Deploy
sudo ./deploy/install.sh
sudo systemctl start chess-data-service
sudo systemctl enable chess-data-service

# Test
curl http://localhost:8787/health
```

### Arch Linux / Manjaro

```bash
# Prerequisites
sudo pacman -Sy git curl zstd base-devel

# Install Mind runtime
curl -sSL https://mindlang.dev/install.sh | sh
export PATH="$PATH:$HOME/.mind/bin"

# Clone and build
git clone <repo>
cd mind-chess-data-service
./build.sh

# Deploy
sudo ./deploy/install.sh
sudo systemctl start chess-data-service
sudo systemctl enable chess-data-service

# Test
curl http://localhost:8787/health
```

### openSUSE

```bash
# Prerequisites
sudo zypper install -y git curl zstd gcc

# Install Mind runtime
curl -sSL https://mindlang.dev/install.sh | sh
export PATH="$PATH:$HOME/.mind/bin"

# Clone and build
git clone <repo>
cd mind-chess-data-service
./build.sh

# Deploy
sudo ./deploy/install.sh
sudo systemctl start chess-data-service
sudo systemctl enable chess-data-service

# Test
curl http://localhost:8787/health
```

## Build

```bash
./build.sh          # Build all
./build.sh server   # Server only
./build.sh tools    # Tools only
./build.sh test     # Run tests
./build.sh clean    # Clean build
```

Produces binaries in `./bin/`

## API

### GET /health
```json
{"ok":true,"book":true,"tb8":false,"nnue":true}
```

### POST /book/query
```json
Request:  {"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","max_moves":10}
Response: {"key":5060803636482931868,"moves":[{"uci":"e2e4","weight":100,"learn":0}]}
```

### POST /tb8/query
```json
Request:  {"fen":"8/8/8/4k3/8/4K3/4P3/8 w - - 0 1"}
Response: {"wdl":2,"dtz":15,"source":"syzygy"}
```
Returns `{"wdl":null,"source":"disabled"}` if TB8 not loaded.

### POST /nnue/query
```json
Request:  {"fen":"..."}
Response: {"key":123,"score":50,"stm":"w"}
```

### POST /admin/reload
```json
Response: {"status":"ok"}
```

## Binary Formats

### Book (Polyglot compatible)
- `book.idx`: sorted `(key:u64, offset:u64, count:u16)` for binary search
- `book.dat`: packed `(key:u64, move:u16, weight:u16, learn:u32)` records

### NNUE Training
- `nnue.bin`: packed `(key:u64, score:i16, result:i8, stm:u8)` records

## Data Import

### Opening Book
```bash
# From Lichess PGN (streaming)
curl -s https://database.lichess.org/standard/lichess_db_standard_rated_2024-01.pgn.zst | \
  zstdcat | import_pgn_to_book --stdin --output /var/lib/chess-data/book/v1/

activate_version book v1
curl -X POST http://localhost:8787/admin/reload
```

### NNUE Data
```bash
generate_nnue_from_pgn \
  --url https://database.lichess.org/standard/lichess_db_standard_rated_2024-01.pgn.zst \
  --output /var/lib/chess-data/nnue/v1/ \
  --target 10000000

activate_version nnue v1
curl -X POST http://localhost:8787/admin/reload
```

## Storage Layout

```
/var/lib/chess-data/
├── book/
│   ├── current -> v1/
│   └── v1/
│       ├── book.idx
│       └── book.dat
├── tb8/
│   └── current -> v1/
└── nnue/
    ├── current -> v1/
    └── v1/
        └── nnue.bin
```

## Configuration

`/etc/chess-data-service/config.toml`:
```toml
[server]
bind = "0.0.0.0:8787"
threads = 4

[data]
root = "/var/lib/chess-data"

[book]
enabled = true
max_moves = 20

[tb8]
enabled = false

[nnue]
enabled = true
```

## Service Management

```bash
# Status
sudo systemctl status chess-data-service

# Logs
sudo journalctl -u chess-data-service -f
cat /var/log/chess-data-service/service.log

# Reload config (hot reload)
curl -X POST http://localhost:8787/admin/reload
# or
sudo systemctl reload chess-data-service

# Restart
sudo systemctl restart chess-data-service
```

## Nikola Integration

Configure in Nikola engine:
```
setoption name BookUrl value http://192.168.1.100:8787
setoption name UseRemoteBook value true
```

Client is fail-open: returns empty on timeout/error.

### Nikola Client Code

The `src/client/nikola_client.mind` module provides a fail-open HTTP client:

```mind
import client.nikola_client

// Initialize from UCI option
nikola_client.init_from_option("http://192.168.1.100:8787")

// Query book (returns empty array on error)
let moves = client.query_book(fen, 10)
for moves |mv| {
    // mv.uci, mv.weight
}

// Query TB8 (returns null wdl on error)
let tb = client.query_tb8(fen)
if tb.wdl != null {
    // Use tablebase result
}
```

## Troubleshooting

### Service won't start
```bash
# Check logs
sudo journalctl -u chess-data-service -n 100
cat /var/log/chess-data-service/error.log

# Check config syntax
cat /etc/chess-data-service/config.toml

# Check permissions
ls -la /var/lib/chess-data/
```

### Port already in use
```bash
# Find process on port 8787
sudo lsof -i :8787
# or
sudo ss -tlnp | grep 8787

# Change port in config
sudo vim /etc/chess-data-service/config.toml
# Edit: bind = "0.0.0.0:8788"
sudo systemctl restart chess-data-service
```

### Firewall blocking connections
```bash
# Ubuntu/Debian (ufw)
sudo ufw allow 8787/tcp

# RHEL/AlmaLinux/Fedora (firewalld)
sudo firewall-cmd --permanent --add-port=8787/tcp
sudo firewall-cmd --reload

# Check from client
curl -v http://server-ip:8787/health
```

### Empty book responses
```bash
# Check book files exist
ls -la /var/lib/chess-data/book/current/

# Re-import book
curl -s https://database.lichess.org/standard/lichess_db_standard_rated_2024-01.pgn.zst | \
  zstdcat | import_pgn_to_book --stdin --output /var/lib/chess-data/book/v2/
activate_version book v2
curl -X POST http://localhost:8787/admin/reload
```

## Community

- **Discussions:** <https://github.com/star-ga/mind/discussions> — questions,
  ideas and help for mind-chess-data-service and the wider MIND ecosystem.
- **Discord:** <https://mindlang.dev/discord> — the MindLang community server.

## License

MIT
