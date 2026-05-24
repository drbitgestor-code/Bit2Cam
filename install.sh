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
GO2RTC_PORT=1984
CONFIG_API_PORT=1985
RTSP_PORT=8554
SERVICE_USER="go2rtc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub — substitua pelo seu repositório após publicar
GITHUB_REPO="https://raw.githubusercontent.com/drbitgestor-code/Bit2Cam/main"

# Tailscale — auth key opcional (pode ser passada como variável de ambiente)
# Exemplo: TAILSCALE_AUTHKEY=tskey-auth-xxxx sudo bash install.sh
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"

# Senha do setup.html — pode ser passada como variável de ambiente
# Exemplo: SETUP_PASSWORD=minhasenha sudo bash install.sh
# Se não passada, o instalador pergunta interativamente
SETUP_PASSWORD="${SETUP_PASSWORD:-}"

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
echo -e "  ${BOLD}BIT2CAM — Instalador para Ubuntu Server${NC}"
echo -e "  go2rtc + Config API + Sync JSON\n"

# ── PRÉ-VERIFICAÇÕES ─────────────────────────────────────────────
section "Verificações"

[[ $EUID -ne 0 ]] && error "Execute como root: sudo bash install.sh"

# Verificar Ubuntu/Debian
if ! command -v apt-get &>/dev/null; then
  error "Este script requer um sistema baseado em Debian/Ubuntu"
fi

# Detectar arquitetura
case "$(uname -m)" in
  x86_64)  GO2RTC_ARCH="amd64" ;;
  aarch64) GO2RTC_ARCH="arm64" ;;
  armv7l)  GO2RTC_ARCH="arm"   ;;
  *)       error "Arquitetura não suportada: $(uname -m)" ;;
esac
success "Arquitetura detectada: $(uname -m) → go2rtc_linux_${GO2RTC_ARCH}"

# Verificar conectividade
info "Verificando conectividade..."
curl -fsSL --max-time 5 https://github.com > /dev/null 2>&1 \
  || error "Sem acesso ao github.com — verifique a conexão"
success "Conectividade OK"

# Informar sobre instalação existente
if [[ -f "$INSTALL_DIR/go2rtc" ]]; then
  warn "Instalação existente detectada em $INSTALL_DIR — será atualizada"
fi

# ── SENHA DO SETUP ───────────────────────────────────────────────
section "Senha do Setup"

if [[ -n "$SETUP_PASSWORD" ]]; then
  info "Usando senha passada por variável de ambiente"
else
  echo -e "  ${CYAN}Defina a senha para o acesso técnico (setup.html).${NC}"
  echo -e "  Deixe em branco para usar o padrão: ${BOLD}bit2cam${NC}"
  echo ""
  while true; do
    read -rsp "  Senha [bit2cam]: " _pwd1; echo
    if [[ -z "$_pwd1" ]]; then
      SETUP_PASSWORD="bit2cam"
      info "Usando senha padrão: bit2cam"
      break
    fi
    read -rsp "  Confirmar senha: " _pwd2; echo
    if [[ "$_pwd1" == "$_pwd2" ]]; then
      SETUP_PASSWORD="$_pwd1"
      success "Senha configurada"
      break
    fi
    warn "Senhas não coincidem — tente novamente"
  done
fi

# ── DEPENDÊNCIAS ─────────────────────────────────────────────────
section "Dependências"

info "Atualizando lista de pacotes..."
apt-get update -qq

PKGS=()
command -v curl   &>/dev/null || PKGS+=(curl)
command -v python3 &>/dev/null || PKGS+=(python3)

if [[ ${#PKGS[@]} -gt 0 ]]; then
  info "Instalando: ${PKGS[*]}"
  apt-get install -y -qq "${PKGS[@]}"
fi
success "Dependências prontas"

# ── USUÁRIO DE SERVIÇO ───────────────────────────────────────────
section "Usuário de serviço"

if ! id "$SERVICE_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /bin/false "$SERVICE_USER"
  success "Usuário '$SERVICE_USER' criado"
else
  success "Usuário '$SERVICE_USER' já existe"
fi

# ── DIRETÓRIOS ───────────────────────────────────────────────────
section "Diretórios"

mkdir -p "$INSTALL_DIR" "$WWW_DIR"
success "Diretório de instalação: $INSTALL_DIR"
success "Diretório do monitor:    $WWW_DIR"

# ── GO2RTC ───────────────────────────────────────────────────────
section "Download go2rtc"

GO2RTC_BIN="$INSTALL_DIR/go2rtc"
GO2RTC_URL="https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_${GO2RTC_ARCH}"

info "Baixando go2rtc (última versão, $GO2RTC_ARCH)..."
if ! curl -fsSL --progress-bar "$GO2RTC_URL" -o "$GO2RTC_BIN"; then
  error "Falha ao baixar go2rtc de $GO2RTC_URL"
fi
chmod +x "$GO2RTC_BIN"
success "go2rtc instalado em $GO2RTC_BIN"

# ── CONFIG go2rtc ────────────────────────────────────────────────
section "Configuração go2rtc"

GO2RTC_YAML="$INSTALL_DIR/go2rtc.yaml"

if [[ ! -f "$GO2RTC_YAML" ]]; then
  cat > "$GO2RTC_YAML" << EOF
api:
  listen: ":${GO2RTC_PORT}"
  static_dir: ${WWW_DIR}

log:
  level: warn

rtsp:
  listen: ":${RTSP_PORT}"
EOF
  success "go2rtc.yaml criado"
else
  # Garantir que static_dir está configurado
  if ! grep -q "static_dir" "$GO2RTC_YAML"; then
    warn "go2rtc.yaml existente encontrado"
    info "Adicionando static_dir ao go2rtc.yaml..."
    # Adicionar sob [api] ou no final
    if grep -q "^api:" "$GO2RTC_YAML"; then
      sed -i "/^api:/a\\  static_dir: ${WWW_DIR}" "$GO2RTC_YAML"
    else
      printf "\napi:\n  static_dir: %s\n" "$WWW_DIR" >> "$GO2RTC_YAML"
    fi
    success "static_dir adicionado ao go2rtc.yaml existente"
  else
    success "go2rtc.yaml já existente — mantendo configuração atual"
  fi
fi

# ── CONFIG JSON ──────────────────────────────────────────────────
CONFIG_JSON="$INSTALL_DIR/config.json"

if [[ ! -f "$CONFIG_JSON" ]]; then
  echo '{"servers":[],"cameras":[],"selectedUids":[]}' > "$CONFIG_JSON"
  success "config.json criado (vazio)"
else
  success "config.json já existe — mantendo dados atuais"
fi

# ── CONFIG API (Python) ───────────────────────────────────────────
section "Config API"

cat > "$INSTALL_DIR/config-api.py" << 'PYEOF'
#!/usr/bin/env python3
"""
GO2RTC Monitor — Config API
GET  /config  → retorna config.json
POST /config  → grava config.json (valida estrutura antes)
"""
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')
PORT        = int(os.environ.get('CONFIG_API_PORT', 1985))
EMPTY_CFG   = '{"servers":[],"cameras":[],"selectedUids":[]}'

CORS_HEADERS = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
}

class Handler(BaseHTTPRequestHandler):
    def _send_cors(self):
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors()
        self.end_headers()

    def do_GET(self):
        if self.path != '/config':
            self.send_response(404)
            self.end_headers()
            return
        try:
            with open(CONFIG_PATH, 'rb') as f:
                data = f.read()
        except FileNotFoundError:
            data = EMPTY_CFG.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', len(data))
        self._send_cors()
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != '/config':
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get('Content-Length', 0))
            body   = self.rfile.read(length)
            parsed = json.loads(body)
            required = ('servers', 'cameras', 'selectedUids')
            if not all(k in parsed and isinstance(parsed[k], (list, dict)) for k in required):
                raise ValueError('estrutura inválida — campos obrigatórios ausentes')
            tmp = CONFIG_PATH + '.tmp'
            with open(tmp, 'w', encoding='utf-8') as f:
                json.dump(parsed, f, ensure_ascii=False, indent=2)
            os.replace(tmp, CONFIG_PATH)  # atômico — evita arquivo corrompido
            self.send_response(204)
            self._send_cors()
            self.end_headers()
        except json.JSONDecodeError as e:
            self._respond_error(400, f'JSON inválido: {e}')
        except ValueError as e:
            self._respond_error(400, str(e))
        except OSError as e:
            self._respond_error(500, f'Erro ao gravar arquivo: {e}')

    def _respond_error(self, code, msg):
        body = msg.encode()
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', len(body))
        self._send_cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass  # silencioso — logs via journald

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', PORT), Handler)
    print(f'Config API ouvindo em http://0.0.0.0:{PORT}/config', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('Encerrado.')
        sys.exit(0)
PYEOF

chmod +x "$INSTALL_DIR/config-api.py"
success "config-api.py criado"

# ── MONITOR HTML ─────────────────────────────────────────────────
section "Monitor HTML"

_copy_html() {
  local file="$1"
  local src="$SCRIPT_DIR/$file"
  local dest="$WWW_DIR/$file"

  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    success "$file copiado da pasta local"
  elif [[ -n "$GITHUB_REPO" && "$GITHUB_REPO" != *"SEU_USUARIO"* ]]; then
    info "$file não encontrado localmente — baixando do GitHub..."
    if curl -fsSL "$GITHUB_REPO/$file" -o "$dest" 2>/dev/null; then
      success "$file baixado do GitHub"
    else
      warn "Falha ao baixar $file do GitHub"
      warn "Copie manualmente para: $dest"
    fi
  else
    warn "$file não encontrado e GITHUB_REPO não configurado"
    warn "Copie manualmente para: $dest"
  fi
}

_copy_html "bit2cam.html"
_copy_html "setup.html"

# Injetar hash da senha no setup.html e bit2cam.html
if [[ -f "$WWW_DIR/setup.html" ]]; then
  SETUP_HASH=$(echo -n "$SETUP_PASSWORD" | sha256sum | awk '{print $1}')
  sed -i "s/const SETUP_HASH = '[^']*'/const SETUP_HASH = '$SETUP_HASH'/" "$WWW_DIR/setup.html"
  sed -i "s/const SETUP_HASH = '[^']*'/const SETUP_HASH = '$SETUP_HASH'/" "$WWW_DIR/bit2cam.html"
  success "Senha do setup configurada"
fi

HTML_DEST="$WWW_DIR/bit2cam.html"

# Placeholder caso o HTML não tenha chegado
if [[ ! -f "$HTML_DEST" ]]; then
  cat > "$WWW_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"><title>GO2RTC Monitor</title>
<style>body{background:#080c10;color:#00d4ff;font-family:monospace;display:flex;
align-items:center;justify-content:center;height:100vh;margin:0;flex-direction:column;gap:16px;}
code{background:#0d1117;padding:6px 12px;border-radius:4px;border:1px solid #1a2f45;}</style>
</head>
<body>
<h2>GO2RTC Monitor</h2>
<p>Copie o arquivo do monitor para este servidor:</p>
<code>scp bit2cam.html usuario@servidor:/opt/go2rtc/www/</code>
</body></html>
EOF
  info "Placeholder criado em $WWW_DIR/index.html"
fi

# ── PERMISSÕES ───────────────────────────────────────────────────
section "Permissões"

chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"
chmod 755 "$WWW_DIR"
chmod 640 "$CONFIG_JSON"
chmod 640 "$GO2RTC_YAML"
chmod 750 "$GO2RTC_BIN"
chmod 750 "$INSTALL_DIR/config-api.py"
success "Permissões configuradas para usuário '$SERVICE_USER'"

# ── SYSTEMD: go2rtc ───────────────────────────────────────────────
section "Serviços systemd"

cat > /etc/systemd/system/go2rtc.service << EOF
[Unit]
Description=go2rtc — Real-Time Streaming Server
Documentation=https://github.com/AlexxIT/go2rtc
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${GO2RTC_BIN} -config ${GO2RTC_YAML}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=go2rtc

[Install]
WantedBy=multi-user.target
EOF
success "go2rtc.service criado"

# ── SYSTEMD: config-api ───────────────────────────────────────────
cat > /etc/systemd/system/go2rtc-config-api.service << EOF
[Unit]
Description=GO2RTC Monitor — Config API
After=network.target
PartOf=go2rtc.service

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
Environment=CONFIG_API_PORT=${CONFIG_API_PORT}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/config-api.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=go2rtc-config-api

[Install]
WantedBy=multi-user.target
EOF
success "go2rtc-config-api.service criado"

# ── ATIVAR E INICIAR ─────────────────────────────────────────────
section "Iniciando serviços"

systemctl daemon-reload

# Parar se já estiver rodando (upgrade)
systemctl stop go2rtc go2rtc-config-api 2>/dev/null || true

systemctl enable --now go2rtc
success "go2rtc iniciado e habilitado no boot"

systemctl enable --now go2rtc-config-api
success "go2rtc-config-api iniciado e habilitado no boot"

# Aguardar subida
sleep 2

# Verificar se subiram
if systemctl is-active --quiet go2rtc; then
  success "go2rtc está rodando"
else
  warn "go2rtc não iniciou — verifique: journalctl -u go2rtc -n 20"
fi

if systemctl is-active --quiet go2rtc-config-api; then
  success "go2rtc-config-api está rodando"
else
  warn "go2rtc-config-api não iniciou — verifique: journalctl -u go2rtc-config-api -n 20"
fi

# ── FIREWALL ─────────────────────────────────────────────────────
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  section "Firewall (ufw)"
  ufw allow ${GO2RTC_PORT}/tcp    comment 'go2rtc HTTP'       > /dev/null
  ufw allow ${RTSP_PORT}/tcp      comment 'go2rtc RTSP'       > /dev/null
  ufw allow ${CONFIG_API_PORT}/tcp comment 'go2rtc Config API' > /dev/null
  success "Regras ufw adicionadas (${GO2RTC_PORT}, ${RTSP_PORT}, ${CONFIG_API_PORT})"
else
  info "ufw não ativo — configure o firewall manualmente se necessário"
fi

# ── TAILSCALE ────────────────────────────────────────────────────
section "Tailscale"

TAILSCALE_IP=""

if command -v tailscale &>/dev/null; then
  success "Tailscale já instalado"
else
  info "Instalando Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  success "Tailscale instalado"
fi

systemctl enable --now tailscaled 2>/dev/null || true

# Verificar se já está conectado
if tailscale status &>/dev/null 2>&1; then
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
  [[ -n "$TAILSCALE_IP" ]] && success "Tailscale já conectado: $TAILSCALE_IP"
fi

# Autenticar se ainda não conectado
if [[ -z "$TAILSCALE_IP" ]]; then
  if [[ -n "$TAILSCALE_AUTHKEY" ]]; then
    info "Autenticando com auth key..."
    tailscale up --authkey="$TAILSCALE_AUTHKEY" --accept-routes --ssh \
      --hostname="go2rtc-$(hostname -s)"
    sleep 3
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [[ -n "$TAILSCALE_IP" ]]; then
      success "Tailscale conectado: $TAILSCALE_IP"
    else
      warn "Tailscale: não foi possível obter IP — verifique a auth key"
    fi
  else
    warn "Auth key não fornecida — autenticação manual necessária"
    echo ""
    echo -e "  Para conectar este nó ao seu Tailnet, execute:"
    echo -e "  ${CYAN}  sudo tailscale up --ssh${NC}"
    echo -e "  Ou passe a auth key direto na instalação:"
    echo -e "  ${CYAN}  TAILSCALE_AUTHKEY=tskey-auth-xxx sudo bash install.sh${NC}"
    echo ""
    info "O flag --ssh habilita acesso SSH via Tailscale sem abrir porta 22 publicamente"
  fi
fi

# ── RESUMO ───────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         Instalação concluída com sucesso!        ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Acesso local (LAN):${NC}"
echo -e "    Monitor:     http://${LOCAL_IP}:${GO2RTC_PORT}/bit2cam.html"
echo -e "    Configuração: http://${LOCAL_IP}:${GO2RTC_PORT}/setup.html"
echo -e "    go2rtc API:  http://${LOCAL_IP}:${GO2RTC_PORT}/api/streams"
echo -e "    Config API:  http://${LOCAL_IP}:${CONFIG_API_PORT}/config"
echo ""
if [[ -n "$TAILSCALE_IP" ]]; then
  echo -e "  ${BOLD}Acesso remoto (Tailscale):${NC}"
  echo -e "    Monitor:     http://${TAILSCALE_IP}:${GO2RTC_PORT}/bit2cam.html"
  echo -e "    Configuração: http://${TAILSCALE_IP}:${GO2RTC_PORT}/setup.html"
  echo -e "    go2rtc API:  http://${TAILSCALE_IP}:${GO2RTC_PORT}/api/streams"
  echo -e "    Config API:  http://${TAILSCALE_IP}:${CONFIG_API_PORT}/config"
  echo ""
else
  echo -e "  ${YELLOW}Tailscale:${NC} não conectado — execute ${CYAN}sudo tailscale up --ssh${NC} para ativar"
  echo ""
fi
echo ""
echo -e "  ${BOLD}Arquivos:${NC}"
echo -e "    Instalação:  ${INSTALL_DIR}"
echo -e "    Monitor:     ${WWW_DIR}/bit2cam.html"
echo -e "    Config:      ${CONFIG_JSON}"
echo -e "    go2rtc.yaml: ${GO2RTC_YAML}"
echo ""
echo -e "  ${BOLD}Gerenciar serviços:${NC}"
echo -e "    systemctl status  go2rtc go2rtc-config-api"
echo -e "    systemctl restart go2rtc go2rtc-config-api"
echo -e "    systemctl stop    go2rtc go2rtc-config-api"
echo ""
echo -e "  ${BOLD}Logs em tempo real:${NC}"
echo -e "    journalctl -u go2rtc -f"
echo -e "    journalctl -u go2rtc-config-api -f"
echo ""
echo -e "  ${CYAN}BIT2CAM Monitor${NC} · Config API sync · localStorage fallback"
echo ""
