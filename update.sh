#!/bin/bash
set -euo pipefail

# ── CORES ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}▸${NC} $*"; }
success() { echo -e "${GREEN}✔${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
error()   { echo -e "${RED}✕${NC} $*"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}━━ $* ━━${NC}"; }

# ── CONFIGURAÇÕES ────────────────────────────────────────────────
INSTALL_DIR="/opt/go2rtc"
WWW_DIR="$INSTALL_DIR/www"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_REPO="https://raw.githubusercontent.com/drbitgestor-code/Bit2Cam/main"

# ── BANNER ───────────────────────────────────────────────────────
echo -e "${CYAN}"
cat << 'BANNER'
   ██████╗  ██████╗ ██████╗ ██████╗ ████████╗ ██████╗
  ██╔════╝ ██╔══██╗╚════██╗██╔══██╗╚══██╔══╝██╔════╝
  ██║  ███╗██║  ██║ █████╔╝██████╔╝   ██║   ██║
  ██║   ██║██║  ██║██╔═══╝ ██╔══██╗   ██║   ██║
  ╚██████╔╝██████╔╝███████╗██║  ██║   ██║   ╚██████╗
   ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝
BANNER
echo -e "${NC}"
echo -e "  ${BOLD}GO2RTC Monitor — Atualização${NC}\n"

# ── PRÉ-VERIFICAÇÕES ─────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute como root: sudo bash update.sh"
[[ -d "$WWW_DIR" ]]        || error "Instalação não encontrada em $INSTALL_DIR — rode install.sh primeiro"
[[ -f "$WWW_DIR/setup.html" ]] || error "setup.html não encontrado em $WWW_DIR"

# ── MENU ─────────────────────────────────────────────────────────
section "O que deseja fazer?"
echo -e "  ${BOLD}[1]${NC} Alterar senha do setup"
echo -e "  ${BOLD}[2]${NC} Atualizar HTMLs + reiniciar serviços"
echo -e "  ${BOLD}[3]${NC} Os dois"
echo ""
read -rp "  Opção [1/2/3]: " OPCAO

case "$OPCAO" in
  1|3) DO_PASSWORD=true  ;;
  2)   DO_PASSWORD=false ;;
  *)   error "Opção inválida: $OPCAO" ;;
esac

case "$OPCAO" in
  2|3) DO_UPDATE=true  ;;
  1)   DO_UPDATE=false ;;
esac

# ── ALTERAR SENHA ────────────────────────────────────────────────
do_change_password() {
  section "Alteração de senha"

  local pwd1 pwd2
  while true; do
    read -rsp "  Nova senha: " pwd1; echo
    [[ -z "$pwd1" ]] && { warn "Senha não pode ser vazia"; continue; }
    read -rsp "  Confirmar senha: " pwd2; echo
    [[ "$pwd1" == "$pwd2" ]] && break
    warn "Senhas não coincidem — tente novamente"
  done

  local hash
  hash=$(echo -n "$pwd1" | sha256sum | awk '{print $1}')
  sed -i "s/const SETUP_HASH = '[^']*'/const SETUP_HASH = '$hash'/" "$WWW_DIR/setup.html"
  success "Senha do setup atualizada"
}

# ── ATUALIZAR HTMLs ──────────────────────────────────────────────
_download_html() {
  local file="$1"
  local src="$SCRIPT_DIR/$file"
  local dest="$WWW_DIR/$file"

  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    success "$file copiado da pasta local"
  else
    info "$file não encontrado localmente — baixando do GitHub..."
    if curl -fsSL --max-time 30 "$GITHUB_REPO/$file" -o "$dest" 2>/dev/null; then
      success "$file baixado do GitHub"
    else
      error "Falha ao baixar $file do GitHub — verifique a conexão"
    fi
  fi
}

do_update_html() {
  section "Atualização de HTMLs"

  # Preservar hash da senha atual antes de sobrescrever o setup.html
  local current_hash
  current_hash=$(grep -oP "const SETUP_HASH = '\K[^']+" "$WWW_DIR/setup.html" 2>/dev/null || true)

  _download_html "bit2cam.html"
  _download_html "setup.html"

  # Re-injetar a senha preservada (ou manter a do arquivo baixado se não havia)
  if [[ -n "$current_hash" ]]; then
    sed -i "s/const SETUP_HASH = '[^']*'/const SETUP_HASH = '$current_hash'/" "$WWW_DIR/setup.html"
    success "Senha preservada no novo setup.html"
  fi

  section "Reiniciando serviços"
  systemctl restart go2rtc go2rtc-config-api 2>/dev/null \
    || systemctl restart go2rtc 2>/dev/null \
    || warn "Não foi possível reiniciar — faça manualmente: systemctl restart go2rtc"

  sleep 1
  if systemctl is-active --quiet go2rtc 2>/dev/null; then
    success "go2rtc reiniciado"
  else
    warn "go2rtc não está ativo — verifique: journalctl -u go2rtc -n 20"
  fi
  if systemctl is-active --quiet go2rtc-config-api 2>/dev/null; then
    success "go2rtc-config-api reiniciado"
  fi
}

# ── EXECUÇÃO ─────────────────────────────────────────────────────
$DO_UPDATE    && do_update_html
# Se os dois: a senha é alterada depois do update (sobrepõe qualquer hash do arquivo baixado)
$DO_PASSWORD  && do_change_password

echo -e "\n${GREEN}${BOLD}✔ Concluído.${NC}\n"
