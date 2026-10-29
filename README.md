# Android Device Farm — macOS

Appium Device Farm para macOS com emuladores Android headless, servidor MCP para integração com Claude Code, e suporte a Robot Framework.

```
┌─────────────────────────────────────────┐
│  Claude Code / Claude Desktop           │
│  (usa as ferramentas MCP)               │
└────────────────┬────────────────────────┘
                 │ stdio (MCP)
        ┌────────▼────────┐
        │  mcp/server.py  │  ← servidor MCP
        │  (Python)       │
        └────────┬────────┘
                 │ HTTP REST
        ┌────────▼─────────────────┐
        │  Appium Hub (Docker)     │  :4723
        │  + appium-device-farm    │  dashboard: /device-farm
        └────────┬─────────────────┘
                 │ ADB TCP
    ┌────────────▼────────────────────────┐
    │  Emuladores headless (macOS nativo) │
    │  pixel_8  galaxy_s24  galaxy_a55…   │
    └─────────────────────────────────────┘
```

## Pré-requisitos

| Ferramenta | Instalação |
|---|---|
| Docker Desktop ≥ 4.x | [docker.com/desktop](https://www.docker.com/products/docker-desktop/) |
| Android Studio / SDK | `brew install --cask android-studio` |
| Python ≥ 3.11 | `brew install python` |
| Java 17 (para AVDManager) | `brew install openjdk@17` |
| scrcpy (opcional) | `brew install scrcpy` |

## Setup rápido

```bash
# 1. Copie e ajuste as variáveis
cp .env.example .env

# 2. Instale as dependências Python (MCP + Robot Framework)
make mcp-install

# 3. Suba o hub Appium
make farm-up

# 4. Suba 2 emuladores headless (primeira vez faz download das imagens ~1.5 GB)
make emulators-up N=2

# 5. Verifique os dispositivos
make farm-status
```

## Estrutura do projeto

```
.
├── infra/
│   ├── appium-hub/          # Dockerfile + config do hub Appium
│   └── docker-compose.yml
├── scripts/
│   ├── emulators.sh         # Gerenciamento de emuladores macOS
│   └── farm-status.sh       # Status do farm
├── mcp/
│   ├── server.py            # Servidor MCP (ferramentas Appium para Claude)
│   └── requirements.txt     # Dependências Python
├── robot/
│   ├── resources/
│   │   ├── AppiumMobile.resource   # Keywords reutilizáveis
│   │   └── Variables.resource      # Variáveis padrão
│   └── tests/
│       └── example/
│           └── android_smoke.robot # Suite de exemplo
├── .mcp.json                # Config MCP para Claude Code / Desktop
├── .env.example             # Template de variáveis de ambiente
└── Makefile
```

## Servidor MCP

O servidor MCP expõe as seguintes ferramentas para o Claude:

| Ferramenta | Descrição |
|---|---|
| `farm_status` | Lista dispositivos no farm com status (free/busy/offline) |
| `get_sessions` | Lista sessões Appium ativas |
| `create_session` | Abre uma sessão Appium (capabilities W3C) |
| `delete_session` | Encerra uma sessão |
| `get_page_source` | Retorna o XML da hierarquia de UI atual |
| `take_screenshot` | Captura screenshot (PNG base64) |
| `find_element` | Localiza elemento por id, xpath, accessibility id… |
| `click_element` | Clica em um elemento |
| `input_text` | Digita texto em um campo |
| `get_element_text` | Lê o texto visível de um elemento |
| `press_key` | Envia KeyEvent Android (HOME=3, BACK=4, ENTER=66…) |
| `swipe` | Executa gesto de swipe por coordenadas |
| `install_app` | Instala um APK no dispositivo da sessão |
| `get_current_activity` | Retorna o package/activity em foco |
| `execute_script` | Executa comandos `mobile:` ou JavaScript |
| `run_robot_tests` | Executa uma suite Robot Framework |
| `list_robot_tests` | Lista suites e testes disponíveis |

### Configurar Claude Code

O arquivo `.mcp.json` na raiz do projeto é lido automaticamente pelo Claude Code. Não é necessária configuração extra.

### Configurar Claude Desktop

Adicione ao `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "appium-device-farm": {
      "command": "python",
      "args": ["-m", "mcp.server"],
      "cwd": "/caminho/para/docker-android-farm-mac",
      "env": {
        "PYTHONPATH": "/caminho/para/docker-android-farm-mac",
        "APPIUM_URL": "http://localhost:4723"
      }
    }
  }
}
```

## Robot Framework

### Executar testes

```bash
# Suite de exemplo
make robot-test SUITE=example/android_smoke.robot \
  APP_PACKAGE=com.example.app APP_ACTIVITY=.MainActivity

# Com APK local
make robot-test SUITE=example/android_smoke.robot \
  APP_PATH=/tmp/myapp.apk

# Só testes com tag "smoke"
python -m robot -i smoke --outputdir robot/results robot/tests/

# Relatório HTML
open robot/results/report.html
```

### Criar novos testes

```robot
*** Settings ***
Resource    ../../resources/AppiumMobile.resource

Suite Setup      Open Android Session
Suite Teardown   Close Android Session


*** Variables ***
${APP_PACKAGE}    com.meuapp
${APP_ACTIVITY}   .MainActivity


*** Test Cases ***

Login Com Credenciais Válidas
    [Tags]    login    smoke
    Wait For Element And Click    id=username
    Input Text    id=username    usuario@teste.com
    Wait For Element And Click    id=password
    Input Text    id=password    senha123
    Press Enter
    Wait For Element    id=home_screen
```

## Makefile — referência rápida

```bash
make up                    # Sobe hub + emuladores
make down                  # Para tudo
make farm-status           # Status dos dispositivos
make emulators-up N=3      # Sobe 3 emuladores
make emulator-view I=1     # Espelha tela do emulador 1 (scrcpy)
make mcp-install           # Instala deps Python
make mcp-start             # Inicia servidor MCP manualmente
make robot-test            # Roda suite exemplo
make robot-list            # Lista todas as suites
```

## Catálogo de dispositivos

Edite `infra/emulators/devices.conf` para adicionar ou modificar dispositivos:

```
# id|name|api|width|height|density|ram_mb
pixel_8|Google Pixel 8|36|1080|2400|420|3072
```

Use `make emulators-list` para ver o catálogo completo.
