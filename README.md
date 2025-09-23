# Appium Failure Helper

[![Ruby](https://img.shields.io/badge/language-ruby-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-beta-yellow.svg)]()

**Appium Failure Helper** é um módulo Ruby destinado a automatizar diagnóstico de falhas em testes de automação mobile com **Appium**. O objetivo é reduzir tempo de triagem, fornecer localizadores confiáveis e coletar artefatos de depuração sem depender do Appium Inspector.

---

## Sumário
- [Visão Geral](#visão-geral)
- [Funcionalidades](#funcionalidades)
- [Arquitetura e Fluxo](#arquitetura-e-fluxo)
- [Instalação](#instalação)
- [Configuração (opcional)](#configuração-opcional)
- [API Pública / Integração](#api-pública--integração)
- [Exemplos de Uso](#exemplos-de-uso)
  - [Cucumber (hook After)](#cucumber-hook-after)
  - [RSpec (after :each)](#rspec-after-each)
- [Formato dos Artefatos Gerados](#formato-dos-artefatos-gerados)
- [Lógica de Geração de XPaths (detalhada)](#lógica-de-geração-de-xpaths-detalhada)
- [Tratamento de Dados e Deduplicação](#tratamento-de-dados-e-deduplicação)
- [Relatório HTML Interativo](#relatório-html-interativo)
- [Logging e Observabilidade](#logging-e-observabilidade)
- [Testes e Qualidade](#testes-e-qualidade)
- [Roadmap e Contribuição](#roadmap-e-contribuição)
- [Licença](#licença)

---

## Visão Geral

No momento em que um teste falha, o módulo realiza, de forma atômica e thread-safe:
1. captura de screenshot,
2. extração do `page_source` completo (XML),
3. varredura da árvore de elementos para gerar localizadores sugeridos,
4. escrita de dois YAMLs (focado e completo) e um relatório HTML que agrega tudo.

Todos os artefatos são salvos em uma pasta timestamped (formato `YYYY_MM_DD_HHMMSS`) dentro de `reports_failure/`.

---

## Funcionalidades

- Captura automática de screenshot PNG.
- Export completo de `page_source` em XML.
- Geração de `failure_analysis_*.yaml` (focado no elemento que falhou).
- Geração de `all_elements_dump_*.yaml` (todos os elementos com localizadores sugeridos).
- Relatório HTML interativo que combine screenshot, XML formatado e lista de localizadores.
- Geração de XPaths otimizados para **Android** e **iOS**.
- Truncamento de atributos longos (configurável).
- Eliminação de elementos duplicados e normalização de atributos.
- Logging via `Logger` do Ruby (Níveis: DEBUG/INFO/WARN/ERROR).
- Configuração via bloco `configure` (opcional).

---

## Arquitetura e Fluxo

1. **Hook de Testes** (Cucumber/RSpec) → invoca `Capture.handler_failure(driver, exception)`
2. **Capture.handler_failure**:
   - estabelece pasta de saída com timestamp;
   - chama `driver.screenshot` (salva PNG);
   - chama `driver.page_source` (salva XML);
   - percorre XML e cria árvore de elementos;
   - para cada elemento gera candidate XPaths aplicando regras por plataforma;
   - grava `failure_analysis_*.yaml` (prioriza elemento indicado) e `all_elements_dump_*.yaml`;
   - monta `report_*.html` agregando tudo.
3. Logs detalhados emitidos durante a execução.

---

## Instalação

**Como gem (exemplo):**

Adicione ao `Gemfile` do projeto:

```ruby
gem 'appium_failure_helper', '~> 0.1.0'
```

Depois:

```bash
bundle install
```

**Ou manual (para uso local):**

Coloque o diretório `appium_failure_helper/` dentro do `lib/` do projeto e faça:

```ruby
require_relative 'lib/appium_failure_helper'
```

---

## API Pública / Integração

### `AppiumFailureHelper::Capture`

```ruby
# handler_failure(driver, exception, options = {})
# - driver: objeto de sessão Appium (Selenium::WebDriver / Appium::Driver)
# - exception: exceção capturada no momento da falha
# - options: hash com overrides (ex: output_dir:)
AppiumFailureHelper::Capture.handler_failure(appium_driver, scenario.exception)
```

### Configuração global

```ruby
AppiumFailureHelper.configure do |c|
  # ver bloco de configuração acima
end
```

---

## Exemplos de Uso

### Cucumber (hook `After`)

```ruby
# features/support/hooks.rb
require 'appium_failure_helper'

After do |scenario|
  if scenario.failed?
    AppiumFailureHelper::Capture.handler_failure(appium_driver, scenario.exception)
  end
end
```

---

## Formato dos Artefatos Gerados

**Pasta:** `reports_failure/<TIMESTAMP>/`

Arquivos gerados (ex.: TIMESTAMP = `2025_09_23_173045`):

```
screenshot_2025_09_23_173045.png
page_source_2025_09_23_173045.xml
failure_analysis_2025_09_23_173045.yaml
all_elements_dump_2025_09_23_173045.yaml
report_2025_09_23_173045.html
```

### Exemplo (simplificado) de `failure_analysis_*.yaml`

```yaml
failed_element:
  platform: android
  summary:
    class: android.widget.Button
    resource_id: com.example:id/submit
    text: "Enviar"
  suggested_xpaths:
    - "//android.widget.Button[@resource-id='com.example:id/submit']"
    - "//android.widget.Button[contains(@text,'Enviar')]"
  capture_metadata:
    screenshot: screenshot_2025_09_23_173045.png
    page_source: page_source_2025_09_23_173045.xml
    timestamp: "2025-09-23T17:30:45Z"
tips: "Priorize resource-id; se ausente, use accessibility id (content-desc) e class+text como fallback."
```

### Exemplo (simplificado) de `all_elements_dump_*.yaml`

```yaml
elements:
  - id_hash: "a1b2c3..."
    class: "android.widget.EditText"
    resource_id: "com.example:id/input_email"
    text: "example@example.com"
    truncated_attributes:
      hint: "Digite seu e-mail..."
    suggested_xpaths:
      - "//*[@resource-id='com.example:id/input_email']"
      - "//android.widget.EditText[contains(@hint,'Digite seu e-mail')]"
```

---

## Lógica de Geração de XPaths (detalhada)

**Princípios gerais**
1. Priorizar identificadores estáveis (resource-id no Android / accessibility id no iOS).
2. Evitar XPaths com `index` como primeira opção (usado apenas como último recurso).
3. Combinar atributos quando necessário para aumentar a especificidade e evitar colisões.
4. Normalizar espaços e truncar textos longos.

**Estratégias por plataforma (ordem de preferência)**

- **Android**
  1. `resource-id` → `//*[@resource-id='com.pkg:id/id']`
  2. `content-desc` / `contentDescription` (accessibility) → `//*[@content-desc='x']`
  3. `class` + `text` → `//android.widget.TextView[@class='...' and contains(normalize-space(@text),'...')]`
  4. `class` + raça de atributos (combinações: enabled, clickable, package)
  5. fallback: `//android.widget.Button[position()=n]` (último recurso)

- **iOS**
  1. `accessibility id` (nome accessibility) → `//*[@name='Submit']`
  2. `label` / `value` → `//*[contains(@label,'...')]`
  3. `type` + `label` → `//XCUIElementTypeButton[@label='OK']`
  4. fallback: hierarquia / indices

**Exemplo de XPath combinado (alta especificidade):**

```xpath
//android.widget.Button[@resource-id='com.example:id/submit' and contains(normalize-space(@text),'Enviar') and @clickable='true']
```

---

## Tratamento de Dados e Deduplicação

- **Truncamento**: atributos com comprimento acima de `attr_truncate_length` são truncados com sufixo `...` para evitar poluição do YAML.
- **Hash único por elemento**: é gerado um hash (sha1) baseado em conjunto de atributos relevantes (class+resource-id+content-desc+text) para identificar duplicados.
- **Remoção de nulos**: atributos vazios ou nulos são omitidos nos YAMLs.
- **Ordenação**: elementos no `all_elements_dump` são ordenados por prioridade de localizador (resource-id primeiro).

---

## Relatório HTML Interativo

O HTML gerado possui:
- Visualização inline do `screenshot` (img tag),
- Painel colapsável com o `page_source` (XML formatado e collapsible),
- Lista navegável de elementos com seus `suggested_xpaths` (botões para copiar),
- Ancoragem que permite focalizar: ao clicar em um XPath, realça o fragmento correspondente no XML (se possível),
- Metadados e link rápido para os YAMLs.

**Observação:** o HTML é gerado de forma estática — para realces dinâmicos é usado JavaScript simples embutido (sem dependências externas).

---

## Logging e Observabilidade

- Usa `Logger` padrão do Ruby:
  - `DEBUG` para detalhamento completo (padrão em modo dev).
  - `INFO` para resumo das ações realizadas.
  - `WARN/ERROR` para problemas durante captura/escrita.
- Exemplos de mensagens:
  - `[INFO] Creating failure report folder: reports_failure/2025_09_23_173045`
  - `[DEBUG] Captured 4123 elements from page_source`
  - `[ERROR] Failed to write screenshot: Permission denied`

---

## Testes e Qualidade

- Estrutura de testes sugerida: RSpec + fixtures com dumps de `page_source` para validar a geração de XPaths.
- Testes unitários para: truncamento, hash de deduplicação, geração de strategies, output YAML válido.
- CI: incluir step que valide YAML/HTML gerados (lint) e execute testes RSpec.

---

## Roadmap e Contribuição

**Funcionalidades previstas**
- Suporte a mapeamento visual (overlay) para apontar elemento sobre screenshot.
- Export para outros formatos (JSON/CSV).
- Integração com ferramentas de observabilidade (Sentry, Datadog).
- Modo headless para gerar relatórios offline em pipelines.

**Como contribuir**
1. Fork no repositório.
2. Crie branch com feature/bugfix.
3. Abra PR com descrição técnica das mudanças e testes.
4. Mantenha o estilo Ruby (RuboCop) e documentação atualizada.

---

## Segurança e Privacidade

- Evite capturar dados sensíveis em ambientes com PII. Implementar filtro por regex para mascarar dados (ex.: emails/telefones) antes de salvar YAMLs.
- Recomendado: executar limpeza em ambientes de produção.

---

## Licença

MIT — veja o arquivo `LICENSE` para os termos.

---