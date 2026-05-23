# Bit2Cam — Documentação do Projeto

Monitor de câmeras IP baseado em go2rtc, com wizard de configuração via ONVIF.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `setup.html` | Wizard técnico — descoberta ONVIF, configuração de streams, manutenção |
| `cameras-v23.html` | Monitor do cliente — visualização em grid, renomeação de câmeras |
| `install.sh` | Instalador para Ubuntu Server headless |
| `archive/cameras-v22.html` | Versão standalone anterior (referência) |

---

## Contexto de deploy

- go2rtc instalado no servidor do **galpão do cliente** (Ubuntu Server)
- HTML servido pelo próprio go2rtc na porta 1984
- **Cliente acessa o monitor da matriz via Tailscale no browser** — sem app instalado
- Sem infraestrutura central — cada galpão é um nó independente

---

## Perfis de acesso

| Perfil | URL | Permissões |
|---|---|---|
| **Técnico** | `/setup.html` | Descoberta ONVIF, adicionar/remover câmeras, manutenção |
| **Cliente** | `/cameras-v23.html` | Visualizar câmeras, renomear câmeras |

`setup.html` deve ser protegido — cliente não deve ver nem acessar.

---

## Premissas fixas

- IPs das câmeras são sempre fixos (DHCP reservation) — IP estável garantido
- Câmeras identificadas pelo `src` `onvif://user:pass@IP` — campo imutável
- Nome de exibição é editável pelo cliente no monitor

---

## Fluxo de uso

```
1. sudo bash install.sh        → instala go2rtc + serviços
2. http://host:1984/setup.html → técnico descobre câmeras e configura
3. http://host:1984/cameras-v23.html → cliente monitora via Tailscale
```

---

## setup.html — Wizard Técnico

Wizard de 4 passos que usa a API nativa do go2rtc para descoberta ONVIF.

| Passo | O que faz |
|---|---|
| **1 · Conectar** | Verifica go2rtc na porta 1984 |
| **2 · Descobrir** | `GET /api/onvif` — WS-Discovery multicast. Adição manual por IP disponível |
| **3 · Credenciais** | Nome, usuário e senha por câmera. Botão Testar chama `GET /api/onvif?src=...` |
| **4 · Finalizar** | `PUT /api/streams` por câmera — persiste no `go2rtc.yaml`. Atualiza `config.json` |

**Requisito:** go2rtc na mesma subrede das câmeras (multicast UDP, não atravessa roteadores).

---

## cameras-v23.html — Monitor do Cliente

| Funcionalidade | Status |
|---|---|
| Grid automático de câmeras | ✓ |
| Suporte a múltiplos servidores go2rtc | ✓ |
| Dual stream (sufixo `_hd` para HD no fullscreen) | ✓ |
| Importação via `GET /api/streams` | ✓ |
| Sidebar com busca e drag-and-drop | ✓ |
| Fullscreen com auto-hide | ✓ |
| Renomeação de câmera pelo cliente | pendente |

### Renomeação de câmeras

Fluxo via API nativa go2rtc:
1. `DELETE /api/streams?src=nomeVelho`
2. `PUT /api/streams?name=nomeNovo&src=onvif://user:pass@IP`

Stream some por milissegundos durante o rename — aceitável.
**Não usar `config.json` paralelo para isso.**

---

## install.sh — Instalador Ubuntu Server

### Uso básico

```bash
sudo bash install.sh
```

### Uso com Tailscale

```bash
TAILSCALE_AUTHKEY=tskey-auth-xxxx sudo bash install.sh
```

### Estrutura instalada

```
/opt/go2rtc/
├── go2rtc              # binário
├── go2rtc.yaml         # streams (câmeras adicionadas via setup.html)
├── config.json         # metadados do monitor (config-api)
├── config-api.py       # GET/POST /config na porta 1985
└── www/
    ├── setup.html       # acesso técnico
    └── cameras-v23.html # acesso cliente
```

### Serviços systemd

| Serviço | Porta |
|---|---|
| `go2rtc` | 1984 |
| `go2rtc-config-api` | 1985 |

---

## API go2rtc utilizada

| Endpoint | Método | Uso |
|---|---|---|
| `GET /api/streams` | GET | Lista streams ativos |
| `GET /api/onvif` | GET | WS-Discovery multicast |
| `GET /api/onvif?src=onvif://...` | GET | Proba câmera, retorna perfis |
| `PUT /api/streams?name=...&src=...` | PUT | Adiciona stream (persiste no YAML) |
| `DELETE /api/streams?src=...` | DELETE | Remove stream (persiste no YAML) |

---

## Próximas tarefas

1. **Separar acesso técnico do cliente** — setup.html protegido, monitor sem funções de setup
2. **Renomeação no monitor** — só isso, nada mais
3. **`update.sh`** — atualiza HTMLs no servidor sem reinstalar tudo

## Backlog (não implementar agora)

- PTZ via interface
- Adaptar para Windows
- Gravação agendada
- Notificação de movimento
- App mobile (PWA)
