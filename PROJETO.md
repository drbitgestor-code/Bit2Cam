# GO2RTC Monitor — Documentação do Projeto

## Arquivos

| Arquivo | Descrição |
|---|---|
| `cameras-v22.html` | Monitor standalone — salva em localStorage, abre direto no browser |
| `cameras-v23.html` | Monitor com Config API — sincroniza com servidor, fallback para localStorage |
| `install.sh` | Instalador para Ubuntu Server headless |

---

## cameras-v22.html — Standalone

Versão autossuficiente. Abre direto no browser via `file://` ou servido localmente.  
Toda a configuração é salva no `localStorage` do browser (`go2rtc_v22`).

### Funcionalidades

- Grid automático de câmeras (layout calculado por `sqrt(n)`)
- Suporte a múltiplos servidores go2rtc com código de cor por servidor
- Dual stream: câmeras com sufixo `_hd` usam alta resolução no fullscreen
- Importação automática de câmeras via `GET /api/streams`
- Scan de rede local para descobrir servidores go2rtc (WebRTC ICE + fetch paralelo)
- Sidebar com busca, seleção e reordenação drag-and-drop
- Fullscreen nativo com auto-hide do header e hot corner (6px no topo)
- Geração de arquivo standalone com config embutida (`generateStandalone`)
- Backup/restore via JSON codificado em Base64

### Segurança (corrigida)
- Função `esc()` sanitiza todos os `innerHTML` com dados do usuário (XSS)
- `streamUrl()` valida esquema `http(s)://` antes de montar URLs
- `importConfig()` valida estrutura do JSON antes de aceitar
- Limpeza de iframes ao aplicar seleção (evita leak de conexões WebRTC)

### UX / Acessibilidade
- Fonte Orbitron no logo (design system cyberpunk)
- Focus rings visíveis em todos os elementos interativos (`:focus-visible`)
- `prefers-reduced-motion` — desativa animações para quem precisar
- `aria-label` em botões sem texto (☰, ⛶, ✕)
- `touch-action: manipulation` em todos os botões (remove delay 300ms no mobile)
- `role="status" aria-live="polite"` no painel de scan
- Scanlines e glow hover nos cards de câmera
- Sidebar se oculta ao entrar em fullscreen e restaura ao sair
- Drag-and-drop aplica a ordem automaticamente (sem precisar clicar em Aplicar)
- Escala tipográfica legível: 11–17px (mínimo 11px para badges, 13px para texto principal)

---

## cameras-v23.html — Config API

Versão para deploy no servidor. Idêntica à v22 com a camada de persistência trocada.

### Diferenças em relação à v22

| | v22 | v23 |
|---|---|---|
| Persistência primária | localStorage | Config API (`POST /config`) |
| Fallback | — | localStorage |
| Compartilhamento entre dispositivos | Não | Sim |
| Indicador de status | Não | Sim (API / SAVING / ERRO / LOCAL) |
| Funciona via `file://` | Sim | Sim (modo local automático) |

### Lógica de persistência

1. **Abertura:** tenta `GET http://hostname:1985/config` com timeout 3s → se falhar, usa localStorage
2. **Save:** grava localStorage imediatamente + debounce 800ms para POST na API
3. **Migração:** lê `go2rtc_v22` do localStorage automaticamente na primeira abertura
4. **`file://`:** detecta o protocolo e usa localStorage puro, sem tentar a API

### Indicador no header

| Estado | Cor | Quando |
|---|---|---|
| `API` verde | Conectado e sincronizado |
| `API` amarelo piscando | Salvando no servidor |
| `ERRO` vermelho | API não respondeu |
| `LOCAL` cinza | Modo local (`file://` ou API indisponível) |

---

## install.sh — Instalador Ubuntu Server

### Uso básico
```bash
# Na mesma pasta que cameras-v23.html
sudo bash install.sh
```

### Uso com Tailscale (headless, sem interação)
```bash
TAILSCALE_AUTHKEY=tskey-auth-xxxx sudo bash install.sh
```

### O que o script faz

1. Verifica root, arquitetura (amd64 / arm64 / arm) e conectividade
2. Instala dependências (`curl`, `python3`)
3. Cria usuário de sistema `go2rtc` (sem shell, sem home)
4. Baixa o binário go2rtc mais recente do GitHub Releases
5. Cria `go2rtc.yaml` com `static_dir` apontando para `www/` (não sobrescreve se existir)
6. Cria `config.json` vazio (não sobrescreve se existir)
7. Cria `config-api.py` — servidor HTTP com GET/POST `/config` e escrita atômica
8. Copia `cameras-v23.html` — tenta local → GitHub → placeholder
9. Configura permissões mínimas para o usuário `go2rtc`
10. Cria e ativa dois serviços systemd
11. Abre portas no `ufw` se estiver ativo
12. Instala e conecta Tailscale (se auth key fornecida)
13. Exibe resumo com URLs locais e remotas

### Estrutura instalada

```
/opt/go2rtc/
├── go2rtc              # binário
├── go2rtc.yaml         # configuração
├── config.json         # câmeras e servidores (gravado pela Config API)
├── config-api.py       # servidor Python — GET/POST /config
└── www/
    └── cameras-v23.html
```

### Serviços systemd

| Serviço | Descrição |
|---|---|
| `go2rtc` | Servidor de streaming, porta 1984 |
| `go2rtc-config-api` | Config API Python, porta 1985 |

```bash
# Gerenciar
systemctl status  go2rtc go2rtc-config-api
systemctl restart go2rtc go2rtc-config-api
systemctl stop    go2rtc go2rtc-config-api

# Logs
journalctl -u go2rtc -f
journalctl -u go2rtc-config-api -f
```

### Configurar antes de publicar no GitHub

Editar `install.sh` linha:
```bash
GITHUB_REPO="https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main"
```

Após preencher, o script baixa `cameras-v23.html` automaticamente do repositório  
quando não encontrar o arquivo na pasta local.

---

## Arquitetura multi-servidor

Cada máquina com go2rtc tem sua própria instalação independente.  
O monitor agrega câmeras de todos os servidores cadastrados.

```
go2rtc Loja Centro  (192.168.1.10:1984)  ←─┐
go2rtc Depósito     (192.168.2.10:1984)  ←─┤── Monitor (cameras-v23.html)
go2rtc Filial Sul   (192.168.3.10:1984)  ←─┘
```

Cada nó tem seu próprio `config.json` local.  
A lista de servidores é configurada no monitor e salva via Config API do nó acessado.

### Acesso remoto via Tailscale

Após instalação com auth key, cada nó aparece no Tailnet com hostname `go2rtc-<maquina>`.  
O monitor pode ser acessado remotamente sem abrir portas publicamente:

```
http://<tailscale-ip>:1984/cameras-v23.html
```

O flag `--ssh` habilitado durante `tailscale up` permite acesso SSH ao nó  
via Tailscale sem precisar expor a porta 22 publicamente.

---

## Pendências / Próximos passos

- [ ] Publicar repositório no GitHub e preencher `GITHUB_REPO` no `install.sh`
- [ ] Gerar auth keys no Tailscale Admin para cada nó remoto
- [ ] Adaptar `install.sh` para Windows (script `.bat` + `config-api.exe` via PyInstaller)
- [ ] Script de atualização (`update.sh`) — baixa nova versão do HTML sem reinstalar tudo
