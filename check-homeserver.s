#!/usr/bin/env bash
# Audit read-only untuk Ubuntu Home Server.
# Tidak menginstal, menghapus, menyalakan, atau mengubah konfigurasi apa pun.

set -uo pipefail

GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
RESET=$'\033[0m'

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

ok()   { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; ((OK_COUNT+=1)); }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; ((WARN_COUNT+=1)); }
fail() { printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$*"; ((FAIL_COUNT+=1)); }
info() { printf '%s[INFO]%s %s\n' "$CYAN" "$RESET" "$*"; }
section() { printf '\n%s\n' "============================================================"; printf '%s\n' "$*"; printf '%s\n' "============================================================"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1"; }
service_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }
version_or_missing() {
  local cmd="$1"
  if has_cmd "$cmd"; then
    "$cmd" 2>&1 | head -n 1
  else
    printf 'not-installed'
  fi
}

section "UBUNTU HOME SERVER - INSTALLATION AUDIT"
printf 'Tanggal : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'Host    : %s\n' "$(hostname)"
printf 'OS      : %s\n' "$(. /etc/os-release 2>/dev/null; printf '%s %s (%s)' "${PRETTY_NAME:-unknown}" "${VERSION_ID:-}" "${VERSION_CODENAME:-}")"
printf 'Kernel  : %s\n' "$(uname -r)"
printf 'Mode    : READ-ONLY (tidak mengubah sistem)\n'

section "1. PAKET DAN TOOL DASAR"
for cmd in bash curl git python3 java ssh; do
  if has_cmd "$cmd"; then
    ok "$cmd tersedia: $(version_or_missing "$cmd")"
  else
    fail "$cmd tidak ditemukan"
  fi
done

if has_cmd node; then
  ok "Node.js: $(node --version)"
else
  warn "Node.js tidak ditemukan"
fi

if has_cmd pnpm; then
  ok "pnpm: $(pnpm --version 2>/dev/null | head -n 1)"
else
  warn "pnpm tidak ditemukan"
fi

if has_cmd corepack; then
  ok "Corepack tersedia"
else
  warn "Corepack tidak ditemukan"
fi

if has_cmd java; then
  JAVA_OUT="$(java -version 2>&1 | head -n 1)"
  ok "Java aktif: $JAVA_OUT"
  for jhome in /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-21-openjdk-amd64; do
    if [[ -x "$jhome/bin/java" ]]; then
      ok "JDK ditemukan: $jhome"
    else
      warn "JDK tidak ditemukan di $jhome"
    fi
  done
else
  fail "Java tidak ditemukan"
fi

section "2. CASAOS"
if has_cmd casaos; then
  ok "Binary CasaOS ditemukan: $(command -v casaos)"
  if [[ -x /usr/bin/casaos ]]; then
    info "Versi paket CasaOS (jika tersedia): $(dpkg-query -W -f='${Version}' casaos 2>/dev/null || echo 'tidak diketahui')"
  fi
else
  fail "Binary CasaOS tidak ditemukan"
fi

CASA_SERVICES=(casaos casaos-gateway casaos-user-service casaos-local-storage casaos-message-bus casaos-app-management)
for svc in "${CASA_SERVICES[@]}"; do
  if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q "${svc}.service"; then
    if service_active "$svc"; then
      ok "$svc.service aktif"
    else
      fail "$svc.service terpasang tetapi tidak aktif (status: $(systemctl is-active "$svc" 2>/dev/null || true))"
    fi
  else
    warn "$svc.service tidak ditemukan"
  fi
done

if [[ -d /var/lib/casaos/appstore/default ]]; then
  ok "Direktori default App Store ditemukan"
else
  warn "Direktori default App Store tidak ditemukan"
fi

section "3. DOCKER DAN CONTAINER"
if has_cmd docker; then
  ok "Docker tersedia: $(docker --version 2>/dev/null)"
  if service_active docker; then
    ok "docker.service aktif"
  else
    warn "docker.service tidak aktif/tidak ada (Docker mungkin dijalankan dengan cara lain)"
  fi

  if docker info >/dev/null 2>&1; then
    ok "Docker daemon dapat diakses"
    if docker compose version >/dev/null 2>&1; then
      ok "Docker Compose: $(docker compose version 2>/dev/null)"
    else
      fail "Docker Compose plugin tidak tersedia"
    fi
    echo
    info "Ringkasan container (termasuk yang berhenti):"
    docker ps -a --format '  {{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | head -n 30
    CONTAINERS="$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)"
    for name in nextcloud mariadb redis; do
      if printf '%s\n' "$CONTAINERS" | grep -Eiq "(^|[-_])${name}([-_]|$)"; then
        CSTATUS="$(docker ps -a --filter "name=${name}" --format '{{.Status}}' 2>/dev/null | head -n 1)"
        if [[ "$CSTATUS" == Up* ]]; then
          ok "Container terkait $name berjalan: $CSTATUS"
        else
          warn "Container terkait $name ada tetapi tidak berjalan: ${CSTATUS:-status tidak diketahui}"
        fi
      else
        warn "Container terkait $name belum ditemukan (nama container mungkin berbeda)"
      fi
    done
  else
    fail "Docker CLI ada tetapi tidak dapat terhubung ke Docker daemon"
  fi
else
  fail "Docker tidak ditemukan"
fi

section "4. TAILSCALE"
if has_cmd tailscale; then
  ok "Tailscale tersedia: $(tailscale version 2>/dev/null | head -n 1)"
  if service_active tailscaled; then
    ok "tailscaled.service aktif"
  else
    fail "tailscaled.service tidak aktif"
  fi
  if tailscale status >/dev/null 2>&1; then
    TAILSCALE_STATUS="$(tailscale status 2>&1 | head -n 1)"
    ok "Tailscale status dapat dibaca: $TAILSCALE_STATUS"
    if tailscale ip -4 >/dev/null 2>&1 && [[ -n "$(tailscale ip -4 2>/dev/null)" ]]; then
      ok "IP Tailscale: $(tailscale ip -4 2>/dev/null | paste -sd ', ' -)"
    else
      warn "Belum ada IP Tailscale; mungkin belum login atau belum menjalankan tailscale up"
    fi
  else
    warn "Status Tailscale belum siap; mungkin belum login atau belum menjalankan tailscale up"
  fi
else
  warn "Tailscale tidak ditemukan"
fi

section "5. KEAMANAN DAN SSH"
for svc in ssh fail2ban unattended-upgrades; do
  if service_active "$svc"; then
    ok "$svc.service aktif"
  else
    warn "$svc.service tidak aktif/tidak ada"
  fi
done

if has_cmd ufw; then
  UFW_STATUS="$(sudo ufw status 2>&1 | head -n 1)"
  if printf '%s' "$UFW_STATUS" | grep -q 'Status: active'; then
    ok "UFW aktif"
  else
    warn "UFW tidak aktif: $UFW_STATUS"
  fi
else
  warn "UFW tidak ditemukan"
fi

if has_cmd fail2ban-client; then
  if sudo fail2ban-client ping >/dev/null 2>&1; then
    ok "Fail2ban merespons"
    sudo fail2ban-client status sshd 2>/dev/null | sed 's/^/  /' || true
  else
    warn "Fail2ban client tersedia tetapi daemon tidak merespons"
  fi
else
  warn "fail2ban-client tidak ditemukan"
fi

section "6. NEXTCLOUD DAN KONFIGURASI"
if [[ -d /opt/nextcloud ]]; then
  ok "/opt/nextcloud ditemukan"
else
  fail "/opt/nextcloud tidak ditemukan"
fi

if [[ -f /opt/nextcloud/.env ]]; then
  ok "/opt/nextcloud/.env ditemukan (isi rahasia tidak ditampilkan)"
  PERMS="$(stat -c '%a' /opt/nextcloud/.env 2>/dev/null || echo unknown)"
  if [[ "$PERMS" == "600" ]]; then
    ok "Permission .env adalah 600"
  else
    warn "Permission .env adalah $PERMS; disarankan 600"
  fi
else
  fail "/opt/nextcloud/.env tidak ditemukan"
fi

if [[ -f /opt/nextcloud/docker-compose.yml || -f /opt/nextcloud/compose.yml || -f /opt/nextcloud/compose.yaml ]]; then
  ok "File Docker Compose Nextcloud ditemukan"
  if has_cmd docker && docker info >/dev/null 2>&1; then
    if (cd /opt/nextcloud && docker compose config -q) >/dev/null 2>&1; then
      ok "Konfigurasi Docker Compose valid"
    else
      warn "Konfigurasi Docker Compose gagal divalidasi (lihat dengan: cd /opt/nextcloud && sudo docker compose config)"
    fi
  fi
else
  warn "File Docker Compose Nextcloud tidak ditemukan"
fi

section "7. PORT DAN JARINGAN"
if has_cmd ss; then
  info "Port TCP yang sedang listen (ringkas):"
  ss -lnt 2>/dev/null | sed -n '1,20p' | sed 's/^/  /'
fi
if has_cmd ip; then
  info "Default route:"
  ip route show default 2>/dev/null | sed 's/^/  /' || true
fi

section "8. LOG INSTALLER"
LOG_FILE="/var/log/homeserver-install.log"
if [[ -f "$LOG_FILE" ]]; then
  ok "Log ditemukan: $LOG_FILE"
  info "Baris terakhir log (rahasia tidak seharusnya ditulis ke log; tetap periksa sebelum membagikan):"
  sudo tail -n 25 "$LOG_FILE" 2>/dev/null | sed -E \
    's/(password|passwd|token|secret|credential)([=: ]+)[^ ]+/\1\2[REDACTED]/Ig' | sed 's/^/  /'
else
  warn "Log installer tidak ditemukan di $LOG_FILE"
fi

section "RINGKASAN"
printf '%s[ OK ]%s OK: %d\n' "$GREEN" "$RESET" "$OK_COUNT"
printf '%s[WARN]%s WARNING: %d\n' "$YELLOW" "$RESET" "$WARN_COUNT"
printf '%s[FAIL]%s FAILED: %d\n' "$RED" "$RESET" "$FAIL_COUNT"
printf '\n'
if (( FAIL_COUNT > 0 )); then
  printf 'Kesimpulan: ada komponen gagal/tidak aktif. Jangan jalankan ulang installer penuh sebelum meninjau hasil ini.\n'
elif (( WARN_COUNT > 0 )); then
  printf 'Kesimpulan: pemeriksaan inti tidak menemukan kegagalan fatal, tetapi ada warning yang perlu ditinjau.\n'
else
  printf 'Kesimpulan: seluruh pemeriksaan yang dibuat lulus. Ini belum menjamin semua aplikasi berfungsi dari browser.\n'
fi
printf 'Catatan: script ini bersifat read-only; status service/container hanya dibaca, tidak diperbaiki otomatis.\n'
