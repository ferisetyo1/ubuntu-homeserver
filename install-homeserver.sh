
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Ubuntu Home Server Bootstrap
# SSH + CasaOS + Docker + Nextcloud + Dev tools + Tailscale + security
# Target: fresh Ubuntu Server 24.04 LTS or newer
# Backup intentionally omitted.

LOG="/var/log/homeserver-install.log"
NC_DIR="/opt/nextcloud"
NC_PORT=8080

if [[ $EUID -ne 0 ]]; then
  echo "Jalankan: sudo bash install-homeserver.sh"
  exit 1
fi

source /etc/os-release
if [[ "$ID" != ubuntu ]]; then
  echo "Script ini khusus Ubuntu."
  exit 1
fi

exec > >(tee -a "$LOG") 2>&1

echo "=== Ubuntu Home Server Bootstrap ==="
export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Update sistem dan paket dasar..."
apt-get update
apt-get install -y \
  openssh-server curl wget ca-certificates gnupg \
  git build-essential python3 python3-pip python3-venv \
  openjdk-17-jdk openjdk-21-jdk \
  ufw fail2ban unattended-upgrades \
  iproute2 openssl

systemctl enable --now ssh

echo "[2/8] Aktifkan update keamanan otomatis..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Jangan reboot otomatis ketika sedang development/build.
if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
  sed -i 's/^Unattended-Upgrade::Automatic-Reboot .*/Unattended-Upgrade::Automatic-Reboot "false";/' \
    /etc/apt/apt.conf.d/50unattended-upgrades || true
fi

systemctl enable --now unattended-upgrades

echo "[3/8] Pasang Fail2ban..."
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

echo "[4/8] Pasang CasaOS..."
if [[ ! -d /etc/casaos ]]; then
  curl -fsSL https://get.casaos.io -o /tmp/casaos-install.sh
  bash /tmp/casaos-install.sh
  rm -f /tmp/casaos-install.sh
else
  echo "CasaOS sudah terdeteksi; tidak memasang ulang."
fi

echo "[5/8] Verifikasi Docker dan Compose..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker tidak ditemukan setelah instalasi CasaOS."
  echo "Periksa log, lalu perbaiki instalasi Docker sebelum melanjutkan."
  exit 1
fi

systemctl enable --now docker
docker compose version

echo "[6/8] Pasang Node.js 24 LTS dan pnpm..."
if ! command -v node >/dev/null 2>&1 ||
   [[ "$(node -p 'Number(process.versions.node.split(".")[0])')" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/node-setup.sh
  bash /tmp/node-setup.sh
  rm -f /tmp/node-setup.sh
  apt-get install -y nodejs
fi

corepack enable
corepack prepare pnpm@latest --activate

echo "[7/8] Pasang Tailscale..."
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
  sh /tmp/tailscale-install.sh
  rm -f /tmp/tailscale-install.sh
fi

systemctl enable --now tailscaled

echo "[8/8] Siapkan Nextcloud..."
mkdir -p "$NC_DIR"
chmod 700 "$NC_DIR"
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
fi

if [[ ! -f compose.yaml ]]; then
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
      - "${NEXTCLOUD_PORT:-8080}:80"
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
fi

docker compose up -d

echo "Mengonfigurasi firewall..."
# Deteksi subnet interface yang memiliki default route.
LAN_IF="$(ip -4 route show default | awk 'NR==1 {print $5}')"
LAN_CIDR=""

if [[ -n "${LAN_IF:-}" ]]; then
  ADDR="$(ip -o -4 addr show dev "$LAN_IF" scope global |
    awk 'NR==1 {print $4}')"
  if [[ -n "$ADDR" ]]; then
    LAN_CIDR="$(python3 -c \
      'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' \
      "$ADDR")"
  fi
fi

# Izinkan layanan hanya dari subnet LAN yang terdeteksi.
# Jangan menjalankan UFW jika subnet LAN tidak bisa dideteksi.
if [[ -n "$LAN_CIDR" ]]; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$LAN_CIDR" to any port 22 proto tcp
  ufw allow from "$LAN_CIDR" to any port 80 proto tcp
  ufw allow from "$LAN_CIDR" to any port 443 proto tcp
  ufw allow from "$LAN_CIDR" to any port "$NC_PORT" proto tcp
  ufw allow in on tailscale0
  ufw --force enable
else
  echo "PERINGATAN: subnet LAN tidak terdeteksi."
  echo "UFW tidak diaktifkan agar akses SSH tidak terkunci."
fi

echo
echo "=== Bootstrap selesai ==="
echo "SSH: ssh USERNAME@IP-SERVER"
echo "CasaOS: http://IP-SERVER/"
echo "Nextcloud: http://IP-SERVER:${NC_PORT}/"
echo "LAN subnet: ${LAN_CIDR:-tidak terdeteksi}"
echo
echo "Login Tailscale dengan menjalankan:"
echo "  sudo tailscale up"
echo
echo "Cek IP Tailscale:"
echo "  tailscale ip -4"
echo
echo "Cek password Nextcloud:"
echo "  sudo grep '^NEXTCLOUD_ADMIN_PASSWORD=' $NC_DIR/.env"
echo
echo "Cek container:"
docker compose ps
echo
echo "PENTING:"
echo "- Jangan membuka port SSH/Nextcloud/CasaOS ke internet melalui router."
echo "- Port Docker yang dipublikasikan dapat melewati UFW."
echo "- Pastikan tidak ada port forwarding publik sebelum menggunakan server."
echo "- SSH password belum dinonaktifkan."
echo "- Backup belum disiapkan sesuai permintaan."
