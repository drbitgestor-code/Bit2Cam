# Bit2Cam — Documentação do Projeto

Monitor de câmeras IP baseado em go2rtc, com wizard de configuração via ONVIF.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `setup.html` | Wizard de primeiro uso — descobre câmeras ONVIF, configura go2rtc e o monitor |
| `cameras-v23.html` | Monitor de câmeras — visualização em grid com sync via Config API |
| `install.sh` | Instalador para Ubuntu Server headless |
| `archive/cameras-v22.html` | Versão standalone anterior (referência) |

---

## Fluxo de uso

```
1. sudo bash install.sh        → instala go2rtc + serviços
2. http://host:1984/setup.html → descobre câmeras e configura tudo
3. http://host:1984/cameras-v23.html → monitora as câmeras
```

---

## setup.html — Wizard de Configuração

Wizard de 4 passos que usa a API nativa do go2rtc para descoberta ONVIF.
Não requer dependências extras além do próprio go2rtc.

### Passos

| Passo | O que faz |
|---|---|
| **1 · Conectar** | Verifica se go2rtc responde na porta 1984. Exibe host, porta e quantidade de streams já configurados. Se falhar, mostra instruções para rodar o `install.sh`. |
| **2 · Descobrir** | Chama `GET /api/onvif` do go2rtc — executa WS-Discovery multicast na rede. Câmeras encontradas aparecem como cards clicáveis. Permite adicionar câmeras manualmente por IP caso não respondam ao multicast. |
| **3 · Credenciais** | Para cada câmera selecionada: nome de exibição, usuário e senha. Botão **Testar** chama `GET /api/onvif?src=onvif://user:pass@ip` e exibe os perfis disponíveis (ex: MainStream 4MP / SubStream 720p) para seleção. |
| **4 · Finalizar** | `PUT /api/streams` em cada câmera — persiste no `go2rtc.yaml`. Atualiza `config.json` via Config API para o monitor. Exibe log linha a linha e botão **Abrir Monitor →**. |

### Como acessar

```
http://<ip-do-servidor>:1984/setup.html
```

### Requisitos

- go2rtc rodando na porta 1984 (instalado via `install.sh`)
- go2rtc na **mesma subrede** das câmeras (WS-Discovery usa multicast UDP, não atravessa roteadores)
- Câmeras com suporte a ONVIF habilitado

### Adicionar câmera manualmente (sem ONVIF)

No passo 2, preencher **IP** e **Porta ONVIF** (padrão 80) e clicar em `+ Adicionar`.
A câmera entra no mesmo fluxo de credenciais dos passos seguintes.

---

## cameras-v23.html — Monitor

Versão principal para deploy no servidor. Sincroniza configuração via Config API
com fallback para localStorage.

### Funcionalidades

- Grid automático de câmeras (layout calculado por `sqrt(n)`)
- Suporte a múltiplos servidores go2rtc com código de cor por servidor
- Dual stream: câmeras com sufixo `_hd` usam alta resolução no fullscreen
- Importação automática de câmeras via `GET /api/streams` do go2rtc
- Scan de rede local para descobrir servidores go2rtc
- Sidebar com busca, seleção e reordenação drag-and-drop
- Fullscreen nativo com auto-hide do header e hot corner (6px no topo)
- Geração de arquivo standalone com config embutida (`generateStandalone`)
- Backup/restore via JSON codificado em Base64

### Persistência

| Estado | Indicador | Descrição |
|---|---|---|
| `API` verde | Conectado e sincronizado com o servidor |
| `API` amarelo | Salvando no servidor (debounce 800ms) |
| `ERRO` vermelho | Config API não respondeu — usando localStorage |
| `LOCAL` cinza | Modo `file://` ou API indisponível |

### Como acessar

```
http://<ip-do-servidor>:1984/cameras-v23.html
```

---

## install.sh — Instalador Ubuntu Server

### Uso básico

```bash
# Na mesma pasta que cameras-v23.html e setup.html
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
8. Copia `cameras-v23.html` e `setup.html` — tenta local → GitHub → placeholder
9. Configura permissões mínimas para o usuário `go2rtc`
10. Cria e ativa dois serviços systemd
11. Abre portas no `ufw` se estiver ativo
12. Instala e conecta Tailscale (se auth key fornecida)
13. Exibe resumo com URLs locais e remotas

### Estrutura instalada

```
/opt/go2rtc/
├── go2rtc              # binário
├── go2rtc.yaml         # configuração (streams adicionados pelo setup.html)
├── config.json         # câmeras e servidores (gravado pela Config API)
├── config-api.py       # servidor Python — GET/POST /config
└── www/
    ├── setup.html       # wizard de configuração
    └── cameras-v23.html # monitor de câmeras
```

### Serviços systemd

| Serviço | Porta | Descrição |
|---|---|---|
| `go2rtc` | 1984 | Servidor de streaming + API |
| `go2rtc-config-api` | 1985 | Config API Python |

```bash
# Status
systemctl status go2rtc go2rtc-config-api

# Reiniciar
systemctl restart go2rtc go2rtc-config-api

# Logs em tempo real
journalctl -u go2rtc -f
journalctl -u go2rtc-config-api -f
```

### Configurar antes de publicar no GitHub

Editar `install.sh` linha 24:
```bash
GITHUB_REPO="https://raw.githubusercontent.com/drbitgestor-code/Bit2Cam/main"
```

Após preencher, o script baixa `cameras-v23.html` e `setup.html` automaticamente
quando não encontrar os arquivos na pasta local.

---

## API go2rtc utilizada

| Endpoint | Método | Uso |
|---|---|---|
| `/api/streams` | GET | Lista streams ativos — usado pelo monitor |
| `/api/onvif` | GET | WS-Discovery multicast — usado pelo setup wizard |
| `/api/onvif?src=onvif://...` | GET | Proba câmera e retorna perfis — usado pelo wizard |
| `/api/streams?name=...&src=...` | PUT | Adiciona stream e persiste no YAML — usado pelo wizard |

---

## Arquitetura multi-servidor

Cada máquina com go2rtc tem sua própria instalação independente.
O monitor agrega câmeras de todos os servidores cadastrados.

```
go2rtc Loja Centro  (192.168.1.10:1984)  ←─┐
go2rtc Depósito     (192.168.2.10:1984)  ←─┤── Monitor (cameras-v23.html)
go2rtc Filial Sul   (192.168.3.10:1984)  ←─┘
```

Cada nó tem seu próprio `go2rtc.yaml` e `config.json`.
O wizard `setup.html` é executado uma vez por nó para configurar as câmeras locais.

### Acesso remoto via Tailscale

```bash
# Instalação com Tailscale
TAILSCALE_AUTHKEY=tskey-auth-xxxx sudo bash install.sh

# Após instalação, acessar pelo IP Tailscale
http://<tailscale-ip>:1984/setup.html       # configuração inicial
http://<tailscale-ip>:1984/cameras-v23.html # monitoramento
```

---

## Pendências / Próximos passos

- [ ] Publicar repositório no GitHub e preencher `GITHUB_REPO` no `install.sh`
- [ ] Gerar auth keys no Tailscale Admin para cada nó remoto
- [ ] Adaptar `install.sh` para Windows (script `.bat` + `config-api.exe` via PyInstaller)
- [ ] Script de atualização (`update.sh`) — baixa nova versão dos HTMLs sem reinstalar tudo
