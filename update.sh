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
echo -e "  ${BOLD}[4]${NC} ${RED}Desinstalar${NC} (remove go2rtc e todos os serviços)"
echo ""
read -rp "  Opção [1/2/3/4]: " OPCAO

case "$OPCAO" in
  1|3) DO_PASSWORD=true  ;;
  2)   DO_PASSWORD=false ;;
  4)   DO_PASSWORD=false ;;
  *)   error "Opção inválida: $OPCAO" ;;
esac

case "$OPCAO" in
  2|3) DO_UPDATE=true  ;;
  1|4) DO_UPDATE=false ;;
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
  local dest="$WWW_DIR/$file"
  local tmp
  tmp=$(mktemp /tmp/bit2cam_XXXXXX.html)
  local bust
  bust=$(date +%s)

  info "Baixando $file do GitHub..."
  if curl -fsSL --max-time 30 "${GITHUB_REPO}/${file}?t=${bust}" -o "$tmp" 2>/dev/null; then
    local lines
    lines=$(wc -l < "$tmp" 2>/dev/null || echo 0)
    if [[ "$lines" -lt 50 ]]; then
      rm -f "$tmp"
      warn "$file: conteúdo inválido ($lines linhas) — usando cópia local"
    else
      mv "$tmp" "$dest"
      local ver
      ver=$(grep -oP "APP_VERSION\s*=\s*'\K[^']+" "$dest" 2>/dev/null || true)
      success "$file atualizado do GitHub${ver:+ (versão: $ver)}"
      return
    fi
  else
    rm -f "$tmp"
    warn "$file: falha no download — usando cópia local"
  fi

  # fallback: cópia local
  local src="$SCRIPT_DIR/$file"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    warn "$file: copiado de $src"
    warn "  → Para garantir a versão mais recente, faça git pull no diretório do projeto"
  else
    error "Falha ao obter $file — GitHub inacessível e sem cópia local em $SCRIPT_DIR"
  fi
}

do_update_html() {
  section "Atualização de HTMLs"

  # Preservar hash da senha atual antes de sobrescrever o setup.html
  local current_hash
  current_hash=$(grep -oP "const SETUP_HASH = '\K[^']+" "$WWW_DIR/setup.html" 2>/dev/null || true)

  _download_html "bit2cam.html"
  _download_html "setup.html"

  # Re-injetar a senha preservada
  if [[ -n "$current_hash" ]]; then
    sed -i "s/const SETUP_HASH = '[^']*'/const SETUP_HASH = '$current_hash'/" "$WWW_DIR/setup.html"
    success "Senha preservada no novo setup.html"
  fi

  section "Reiniciando serviços"
  if systemctl restart go2rtc 2>/dev/null; then
    systemctl restart go2rtc-config-api 2>/dev/null || true
    sleep 2
    systemctl is-active --quiet go2rtc && success "go2rtc reiniciado" \
      || warn "go2rtc não está ativo — verifique: journalctl -u go2rtc -n 20"
    systemctl is-active --quiet go2rtc-config-api 2>/dev/null && success "go2rtc-config-api reiniciado" || true
  else
    warn "Não foi possível reiniciar go2rtc — faça manualmente: systemctl restart go2rtc"
  fi

  # Verificar que go2rtc está servindo o arquivo atualizado
  sleep 1
  local served_lines
  served_lines=$(curl -fsSL --max-time 5 "http://localhost:${GO2RTC_PORT:-1984}/bit2cam.html" 2>/dev/null | wc -l || echo 0)
  if [[ "$served_lines" -gt 50 ]]; then
    success "go2rtc está servindo bit2cam.html ($served_lines linhas) ✓"
  else
    warn "Não foi possível verificar o conteúdo servido — acesse http://localhost:1984/bit2cam.html para confirmar"
  fi
}

# ── DESINSTALAR ──────────────────────────────────────────────────
do_uninstall() {
  section "Desinstalação"

  warn "Esta operação irá remover o BIT2CAM, go2rtc e todos os serviços associados."
  warn "Os dados de câmeras em $INSTALL_DIR/config.json serão APAGADOS."
  echo ""
  read -rp "  Confirma a desinstalação? [s/N]: " confirm
  [[ "${confirm,,}" != "s" ]] && { info "Desinstalação cancelada."; exit 0; }

  info "Parando e desativando serviços..."
  systemctl stop go2rtc go2rtc-config-api 2>/dev/null || true
  systemctl disable go2rtc go2rtc-config-api 2>/dev/null || true
  success "Serviços parados"

  info "Removendo arquivos de serviço..."
  rm -f /etc/systemd/system/go2rtc.service
  rm -f /etc/systemd/system/go2rtc-config-api.service
  systemctl daemon-reload
  success "Arquivos de serviço removidos"

  info "Removendo diretório de instalação..."
  rm -rf "$INSTALL_DIR"
  success "Diretório $INSTALL_DIR removido"

  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    info "Removendo regras do firewall..."
    ufw delete allow 1984/tcp > /dev/null 2>&1 || true
    ufw delete allow 8554/tcp > /dev/null 2>&1 || true
    ufw delete allow 1985/tcp > /dev/null 2>&1 || true
    success "Regras ufw removidas"
  fi

  echo ""
  echo -e "${GREEN}${BOLD}✔ BIT2CAM desinstalado com sucesso.${NC}"
  echo -e "  ${YELLOW}go2rtc e go2rtc-config-api foram removidos.${NC}"
  echo -e "  Tailscale foi mantido — remova manualmente se necessário."
  echo ""
}

# ── EXECUÇÃO ─────────────────────────────────────────────────────
[[ "$OPCAO" == "4" ]] && do_uninstall && exit 0

$DO_UPDATE    && do_update_html
# Se os dois: a senha é alterada depois do update (sobrepõe qualquer hash do arquivo baixado)
$DO_PASSWORD  && do_change_password

echo -e "\n${GREEN}${BOLD}✔ Concluído.${NC}\n"
