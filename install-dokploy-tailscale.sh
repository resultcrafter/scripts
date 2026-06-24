#!/bin/bash
set -euo pipefail

# install-dokploy-tailscale.sh
# One-command Dokploy + Tailscale installer
# Usage: curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash
#        curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash -s -- --ts-key tskey-xxx
#        curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash -s -- --no-tailscale

# ─── Colors ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Parse args ──────────────────────────────────────
TS_KEY=""
SKIP_TS=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --ts-key) TS_KEY="$2"; shift 2 ;;
    --no-tailscale) SKIP_TS=true; shift ;;
    *) shift ;;
  esac
done

# ─── Banner ──────────────────────────────────────────
print_banner() {
  echo -e "${CYAN}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║  Dokploy + Tailscale Installer                ║"
  echo "  ║  Deploy AI infrastructure in minutes           ║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ─── OS Detection ────────────────────────────────────
detect_os() {
  local os_type=""
  case "$(uname -s)" in
    Darwin*) os_type="macos" ;;
    Linux*)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        os_type="wsl"
      else
        os_type="linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) os_type="windows" ;;
    *) os_type="unknown" ;;
  esac
  echo "$os_type"
}

# ─── macOS Guide ─────────────────────────────────────
macos_guide() {
  echo -e "${YELLOW}${BOLD}Dokploy requires Linux. You're on macOS.${NC}"
  echo ""
  echo -e "${BOLD}Option A: Multipass (recommended)${NC}"
  echo "  1. Install Multipass:"
  echo "     brew install --cask multipass"
  echo ""
  echo "  2. Create a Linux VM:"
  echo "     multipass launch --name dokploy --cpus 2 --memory 4G --disk 30G"
  echo ""
  echo "  3. Enter the VM:"
  echo "     multipass shell dokploy"
  echo ""
  echo -e "  4. ${GREEN}Run this script inside the VM:${NC}"
  echo "     curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash"
  echo ""
  echo -e "${BOLD}Option B: Dokploy Cloud${NC}"
  echo "  Skip server management entirely."
  echo "  https://dokploy.com → Cloud → ~\$4.50/month"
  echo ""
  echo -e "${BOLD}Option C: Rent a VPS${NC}"
  echo "  DigitalOcean, Hetzner, Vultr — any Linux server with 2GB+ RAM."
  echo "  Then run this script there."
  echo ""
  exit 0
}

# ─── Windows Guide ───────────────────────────────────
windows_guide() {
  echo -e "${YELLOW}${BOLD}Dokploy requires Linux. You're on Windows.${NC}"
  echo ""
  echo -e "${BOLD}Option A: WSL (recommended)${NC}"
  echo "  1. Open Command Prompt as Administrator"
  echo "  2. Run: wsl --install"
  echo "  3. Restart your computer"
  echo "  4. Open Ubuntu from Start menu"
  echo -e "  5. ${GREEN}Run this script inside WSL:${NC}"
  echo "     curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash"
  echo ""
  echo -e "${BOLD}Option B: Dokploy Cloud${NC}"
  echo "  https://dokploy.com → Cloud → ~\$4.50/month"
  echo ""
  exit 0
}

# ─── Prerequisites Check ────────────────────────────
check_prerequisites() {
  echo -e "${BLUE}Checking prerequisites...${NC}"

  local errors=0

  # Root check
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}  Error: Run as root (use sudo)${NC}"
    errors=$((errors + 1))
  fi

  # RAM check (2GB minimum)
  local ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
  if [ "$ram_mb" -lt 1900 ]; then
    echo -e "${RED}  Error: Need 2GB+ RAM, found ${ram_mb}MB${NC}"
    errors=$((errors + 1))
  else
    echo -e "${GREEN}  RAM: ${ram_mb}MB ✓${NC}"
  fi

  # Disk check (30GB minimum)
  local disk_gb=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
  if [ "$disk_gb" -lt 30 ]; then
    echo -e "${RED}  Error: Need 30GB+ disk, found ${disk_gb}GB${NC}"
    errors=$((errors + 1))
  else
    echo -e "${GREEN}  Disk: ${disk_gb}GB free ✓${NC}"
  fi

  if [ "$errors" -gt 0 ]; then
    echo -e "${RED}Prerequisites not met. Fix the errors above.${NC}"
    exit 1
  fi
  echo -e "${GREEN}All prerequisites met ✓${NC}"
  echo ""
}

# ─── Install Docker ──────────────────────────────────
install_docker() {
  if command -v docker &>/dev/null; then
    echo -e "${GREEN}Docker already installed ✓${NC}"
    return
  fi

  echo -e "${BLUE}Installing Docker...${NC}"
  if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq docker.io
  elif command -v yum &>/dev/null; then
    yum install -y docker
  elif command -v dnf &>/dev/null; then
    dnf install -y docker
  else
    echo -e "${BLUE}Using Docker install script...${NC}"
    curl -fsSL https://get.docker.com | sh
  fi

  systemctl enable docker
  systemctl start docker
  echo -e "${GREEN}Docker installed ✓${NC}"
}

# ─── Install Dokploy ────────────────────────────────
install_dokploy() {
  if command -v dokploy &>/dev/null || docker ps --filter "name=dokploy" --format '{{.Names}}' | grep -q dokploy 2>/dev/null; then
    echo -e "${GREEN}Dokploy already installed ✓${NC}"
    return
  fi

  echo -e "${BLUE}Installing Dokploy...${NC}"
  curl -sSL https://dokploy.com/install.sh | bash

  echo -e "${BLUE}Waiting for Dokploy to start (may take 30-60s)...${NC}"
  local retries=0
  while [ $retries -lt 60 ]; do
    if curl -sf http://localhost:3000 -o /dev/null 2>/dev/null; then
      echo -e "${GREEN}Dokploy is ready ✓${NC}"
      return
    fi
    sleep 2
    retries=$((retries + 1))
    if [ $((retries % 10)) -eq 0 ]; then
      echo -e "  ${YELLOW}Still waiting... (${retries}s elapsed)${NC}"
    fi
  done

  echo -e "${YELLOW}Dokploy is still starting. Check status:${NC}"
  echo "  docker ps | grep dokploy"
  echo "  docker logs dokploy"
}

# ─── Install Tailscale ──────────────────────────────
install_tailscale() {
  if [ "$SKIP_TS" = true ]; then
    echo -e "${YELLOW}Skipping Tailscale (--no-tailscale)${NC}"
    return 1
  fi

  echo -e "${BLUE}Installing Tailscale...${NC}"
  curl -fsSL https://tailscale.com/install.sh | sh

  if command -v tailscale &>/dev/null; then
    echo -e "${GREEN}Tailscale installed ✓${NC}"
    return 0
  else
    echo -e "${YELLOW}Tailscale installation may have failed. Continuing without Tailscale.${NC}"
    return 1
  fi
}

# ─── Connect Tailscale ──────────────────────────────
connect_tailscale() {
  if [ "$SKIP_TS" = true ]; then
    return
  fi

  # If key not provided via arg, ask if user wants Tailscale
  if [ -z "$TS_KEY" ]; then
    echo ""
    echo -e "${BOLD}${CYAN}Tailscale Setup (Optional)${NC}"
    echo ""
    echo "Would you like to set up Tailscale? (free, private VPN access)"
    echo "  - Access Dokploy securely from any device"
    echo "  - No public exposure needed"
    echo "  - Free plan: 6 users, 100 devices"
    echo ""
    read -p "$(echo -e ${BOLD}'Set up Tailscale? [Y/n]: '${NC})" ts_choice

    if [[ "$ts_choice" =~ ^[Nn] ]]; then
      echo -e "${YELLOW}Skipping Tailscale. You can set it up later:${NC}"
      echo "  curl -fsSL https://tailscale.com/install.sh | sh"
      echo "  sudo tailscale up"
      SKIP_TS=true
      return
    fi

    echo ""
    echo -e "${BOLD}How to get an auth key:${NC}"
    echo "  1. Sign up free: https://login.tailscale.com/start"
    echo "  2. Go to: https://login.tailscale.com/admin/settings/keys"
    echo "  3. Click 'Generate auth key'"
    echo "  4. Check: 'Ephemeral' (auto-cleans dead nodes)"
    echo "  5. Check: 'Reusable' (survives restarts)"
    echo "  6. Copy the key (starts with tskey-...)"
    echo ""
    read -p "$(echo -e ${BOLD}'Paste your Tailscale auth key (or press Enter to skip): '${NC})" TS_KEY
  fi

  if [ -z "$TS_KEY" ]; then
    echo -e "${YELLOW}No Tailscale key provided. You can connect later:${NC}"
    echo "  sudo tailscale up"
    return
  fi

  echo -e "${BLUE}Connecting to Tailscale...${NC}"
  tailscale up --authkey "$TS_KEY" --accept-routes 2>/dev/null || {
    echo -e "${YELLOW}Standard connection failed, trying with sudo...${NC}"
    sudo tailscale up --authkey "$TS_KEY" --accept-routes
  }

  echo -e "${GREEN}Connected to Tailscale ✓${NC}"
}

# ─── Get Server IPs ──────────────────────────────────
get_ips() {
  local ts_ip=""
  local pub_ip=""

  if command -v tailscale &>/dev/null; then
    ts_ip=$(tailscale ip -4 2>/dev/null || echo "")
  fi

  pub_ip=$(curl -sf https://api.ipify.org 2>/dev/null || curl -sf https://ifconfig.me 2>/dev/null || echo "unknown")

  echo "$ts_ip|$pub_ip"
}

# ─── Success Message ─────────────────────────────────
print_success() {
  local ips
  ips=$(get_ips)
  local ts_ip="${ips%%|*}"
  local pub_ip="${ips##*|}"

  echo ""
  echo -e "${GREEN}"
  echo "  ╔═══════════════════════════════════════════════════╗"
  echo "  ║                                                   ║"
  echo "  ║   ✅  Dokploy installed successfully!              ║"
  echo "  ║                                                   ║"
  echo "  ║   ───────────────────────────────────────────      ║"

  if [ -n "$ts_ip" ]; then
    echo "  ║                                                   ║"
    echo "  ║   🌐 Tailscale access (private, encrypted):       ║"
    printf "  ║      http://%s:3000\n" "$ts_ip"
    echo "  ║      (from any device on your Tailscale network) ║"
  fi

  echo "  ║                                                   ║"
  echo "  ║   🌐 Public access:                               ║"
  printf "  ║      http://%s:3000\n" "$pub_ip"
  echo "  ║      (use Chrome/Firefox, not Safari for HTTP)   ║"
  echo "  ║                                                   ║"
  echo "  ║   ───────────────────────────────────────────      ║"
  echo "  ║                                                   ║"
  echo "  ║   Next steps:                                     ║"
  echo "  ║   1. Open the URL above in your browser           ║"
  echo "  ║   2. Create admin account                         ║"
  echo "  ║   3. Add SSH key                                  ║"
  echo "  ║   4. Create server → press 'Setup Server'         ║"
  echo "  ║                                                   ║"
  if [ -n "$ts_ip" ]; then
    echo "  ║   ───────────────────────────────────────────      ║"
    echo "  ║                                                   ║"
    echo "  ║   📱 Access from your laptop/phone:               ║"
    echo "  ║   - Install Tailscale app (tailscale.com/download)║"
    echo "  ║   - Login to same account                        ║"
    printf "  ║   - Open http://%s:3000\n" "$ts_ip"
    echo "  ║                                                   ║"
  fi

  echo "  ║   ───────────────────────────────────────────      ║"
  echo "  ║                                                   ║"
  echo "  ║   Tailscale status:  tailscale status             ║"
  echo "  ║   Tailscale IP:      tailscale ip -4              ║"
  echo "  ║   Dokploy logs:      docker logs dokploy          ║"
  echo "  ║                                                   ║"
  echo "  ╚═══════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ─── Main ────────────────────────────────────────────
main() {
  print_banner

  local os
  os=$(detect_os)

  case "$os" in
    macos) macos_guide ;;
    windows) windows_guide ;;
    wsl)
      echo -e "${GREEN}Running in WSL — Linux detected ✓${NC}"
      echo -e "${YELLOW}Note: For production, a dedicated Linux server is recommended.${NC}"
      echo ""
      ;;
    linux) echo -e "${GREEN}Linux detected ✓${NC}" ;;
    *)
      echo -e "${RED}Unknown OS. This script supports Linux, macOS, and Windows (WSL).${NC}"
      exit 1
      ;;
  esac

  check_prerequisites
  install_docker
  install_dokploy

  if install_tailscale; then
    connect_tailscale
  fi

  print_success
}

main "$@"
