#!/usr/bin/env bash
# Ubuntu Home Server Bootstrap - rerunnable/idempotent edition
# Ubuntu + CasaOS + Docker + Node.js/pnpm + Tailscale + Nextcloud
# Does not reset existing Nextcloud credentials or delete Docker volumes.

set -Eeuo pipefail
umask 077

LOG="/var/log/homeserver-install.log"
NC_DIR="/opt/nextcloud"
NC_PORT="${NEXTCLOUD_PORT:-8080}"
NODE_MAJOR=24
CASA_SERVICES=(casaos casaos-gateway casaos-user-service casaos-local-storage casaos-message-bus casaos-app-management)

if [[ $EUID -ne 0 ]]; then
  echo "Jalankan: sudo bash install-homeserver.sh"
  exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Script ini khusus Ubuntu."
  exit 1
fi

exec > >(tee -a "$LOG") 2>&1
export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date '+%F %T')] $*"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1"; }

casaos_all_active() {
  local svc
  for svc in "${CASA_SERVICES[@]}"; do
    service_active "$svc" || return 1
  done
  return 0
}

log "=== Ubuntu Home Server Bootstrap (rerunnable) ==="
log "OS: ${PRETTY_NAME:-Ubuntu} (${VERSION_CODENAME:-unknown})"
log "Log: $LOG"

log "[1/8] Update sistem dan paket dasar..."
apt-get update
apt-get install -y \
  openssh-server curl wget ca-certificates gnupg \
  git build-essential python3 python3-pip python3-venv \
  openjdk-17-jdk openjdk-21-jdk \
  ufw fail2ban unattended-upgrades \
  iproute2 openssl

systemctl enable --now ssh

log "[2/8] Aktifkan update keamanan otomatis..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
  if grep -q 'Unattended-Upgrade::Automatic-Reboot' /etc/apt/apt.conf.d/50unattended-upgrades; then
    sed -i 's|^[[:space:]]*Unattended-Upgrade::Automatic-Reboot .*|Unattended-Upgrade::Automatic-Reboot "false";|' \
      /etc/apt/apt.conf.d/50unattended-upgrades
  else
    printf '\nUnattended-Upgrade::Automatic-Reboot "false";\n' >> /etc/apt/apt.conf.d/50unattended-upgrades
  fi
fi
systemctl enable --now unattended-upgrades || log "WARNING: service unattended-upgrades tidak tersedia; paket/config tetap terpasang."

log "[3/8] Pasang Fail2ban..."
install -d -m 0755 /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

log "[4/8] Periksa CasaOS..."
if casaos_all_active; then
  log "CasaOS sudah terpasang dan semua layanan inti aktif; melewati installer."
elif [[ -d /etc/casaos ]]; then
  log "WARNING: konfigurasi CasaOS ada tetapi tidak semua layanan aktif."
  log "Tidak menjalankan ulang installer CasaOS otomatis agar tidak merusak instalasi yang ada."
  for svc in "${CASA_SERVICES[@]}"; do
    log "  $svc: $(systemctl is-active "$svc" 2>/dev/null || true)"
  done
else
  log "CasaOS belum terdeteksi; menjalankan installer resmi."
  curl -fsSL https://get.casaos.io -o /tmp/casaos-install.sh
  if bash /tmp/casaos-install.sh; then
    log "Installer CasaOS selesai."
  else
    log "WARNING: installer CasaOS mengembalikan error."
    if casaos_all_active; then
      log "Layanan inti CasaOS aktif; melanjutkan komponen lain. Periksa App Store secara terpisah."
    else
      log "Layanan CasaOS belum semuanya aktif. Tidak akan mencoba instal ulang otomatis."
      log "Melanjutkan hanya jika Docker sudah tersedia; perbaiki CasaOS secara terpisah."
    fi
  fi
  rm -f /tmp/casaos-install.sh
fi

log "[5/8] Verifikasi Docker dan Compose..."
if ! has_cmd docker; then
  log "ERROR: Docker tidak ditemukan. CasaOS biasanya memasangnya; perbaiki Docker/CasaOS lalu jalankan ulang."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  log "ERROR: Docker Compose plugin tidak tersedia."
  exit 1
fi
systemctl enable --now docker
docker compose version
if ! docker info >/dev/null 2>&1; then
  log "ERROR: Docker daemon tidak bisa diakses."
  exit 1
fi

log "[6/8] Pasang Node.js ${NODE_MAJOR} dan pnpm..."
CURRENT_NODE_MAJOR=0
if has_cmd node; then
  CURRENT_NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
fi
if (( CURRENT_NODE_MAJOR < NODE_MAJOR )); then
  curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/node-setup.sh
  if bash /tmp/node-setup.sh; then
    apt-get install -y nodejs
  else
    log "ERROR: setup repository NodeSource gagal pada ${VERSION_CODENAME:-unknown}."
    log "Script dihentikan sebelum Nextcloud agar kegagalan repository tidak disembunyikan."
    rm -f /tmp/node-setup.sh
    exit 1
  fi
  rm -f /tmp/node-setup.sh
fi

if ! has_cmd corepack; then
  log "ERROR: Corepack tidak tersedia setelah Node.js dipasang."
  exit 1
fi
corepack enable
corepack prepare pnpm@latest --activate
node --version
pnpm --version

log "[7/8] Pasang Tailscale..."
if ! has_cmd tailscale; then
  curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
  sh /tmp/tailscale-install.sh
  rm -f /tmp/tailscale-install.sh
fi
systemctl enable --now tailscaled
if tailscale status >/dev/null 2>&1; then
  log "Tailscale terpasang; status tersedia. Jika belum login, jalankan: sudo tailscale up"
else
  log "Tailscale terpasang dan daemon aktif, tetapi belum login/terhubung."
  log "Setelah script selesai, jalankan: sudo tailscale up"
fi

log "[8/8] Siapkan Nextcloud..."
install -d -m 0700 "$NC_DIR"
cd "$NC_DIR"

if [[ ! -f .env ]]; then
  {
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'MYSQL_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'NEXTCLOUD_ADMIN_USER=admin\n'
    printf 'NEXTCLOUD_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'NEXTCLOUD_PORT=%s\n' "$NC_PORT"
  } > .env
  chmod 600 .env
  log "Membuat .env baru dengan password acak."
else
  chmod 600 .env
  log "File .env sudah ada; mempertahankan kredensial yang ada."
fi

if [[ ! -f compose.yaml && ! -f docker-compose.yml && ! -f compose.yml ]]; then
  cat > compose.yaml <<'YAML'
services:
  db:
    image: mariadb:lts
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?Missing password}
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:?Missing password}
    volumes:
      - db:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
  redis:
    image: redis:alpine
    restart: unless-stopped
  app:
    image: nextcloud:apache
    restart: unless-stopped
    ports:
      - "127.0.0.1:${NEXTCLOUD_PORT:-8080}:80"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    environment:
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:?Missing password}
      MYSQL_HOST: db
      REDIS_HOST: redis
      NEXTCLOUD_ADMIN_USER: ${NEXTCLOUD_ADMIN_USER:-admin}
      NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD:?Missing password}
    volumes:
      - nextcloud:/var/www/html
volumes:
  db:
  nextcloud:
YAML
  log "Membuat compose.yaml; port Nextcloud dibatasi ke localhost untuk mengurangi paparan jaringan."
else
  log "File Compose sudah ada; tidak ditimpa."
  log "Periksa binding port-nya secara manual sebelum membuka akses jaringan."
fi

docker compose config -q
docker compose up -d

log "Konfigurasi firewall..."
# Jika UFW sudah aktif, jangan mengubah rule secara otomatis saat rerun.
# Ini mencegah duplikasi rule dan mengurangi risiko mengunci akses SSH.
if ufw status 2>/dev/null | grep -q '^Status: active'; then
  log "UFW sudah aktif; mempertahankan aturan yang ada."
else
  LAN_IF="$(ip -4 route show default | awk 'NR==1 {print $5}')"
  LAN_CIDR=""
  if [[ -n "${LAN_IF:-}" ]]; then
    ADDR="$(ip -o -4 addr show dev "$LAN_IF" scope global | awk 'NR==1 {print $4}')"
    if [[ -n "$ADDR" ]]; then
      LAN_CIDR="$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' "$ADDR")"
    fi
  fi

  if [[ -n "$LAN_CIDR" ]]; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow from "$LAN_CIDR" to any port 22 proto tcp
    ufw allow from "$LAN_CIDR" to any port 80 proto tcp
    ufw allow from "$LAN_CIDR" to any port 443 proto tcp
    ufw allow in on tailscale0
    ufw --force enable
    log "UFW diaktifkan dengan akses LAN untuk SSH/CasaOS; Nextcloud dibatasi localhost."
  else
    log "WARNING: subnet LAN tidak terdeteksi; UFW tidak diaktifkan agar akses SSH tidak terkunci."
  fi
fi

log "=== Bootstrap selesai ==="
echo
echo "CasaOS:      http://IP-SERVER/"
echo "Nextcloud:   hanya localhost pada port ${NC_PORT} secara default"
echo "Akses Nextcloud lewat SSH tunnel dari komputer klien:"
echo "  ssh -L ${NC_PORT}:127.0.0.1:${NC_PORT} USERNAME@IP-SERVER"
echo "  lalu buka http://localhost:${NC_PORT}/"
echo
echo "Login Tailscale jika belum terhubung:"
echo "  sudo tailscale up"
echo
echo "Cek password admin Nextcloud (jangan bagikan output ini):"
echo "  sudo grep '^NEXTCLOUD_ADMIN_PASSWORD=' ${NC_DIR}/.env"
echo
echo "Cek container:"
docker compose ps
echo
echo "PENTING:"
echo "- Jangan membuka port SSH/Nextcloud/CasaOS ke internet melalui router."
echo "- Port Docker yang dipublikasikan bisa melewati UFW; Nextcloud baru dibatasi ke localhost."
echo "- File .env dan Docker volumes yang sudah ada tidak dihapus."
echo "- UFW yang sudah aktif tidak diubah otomatis."
echo "- Installer CasaOS yang gagal pada App Store dapat meninggalkan error App Store; layanan inti diperiksa terpisah."
