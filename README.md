
# Appium Failure Helper: Diagnóstico Inteligente de Falhas

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)  
![Gem Version](https://badge.fury.io/rb/appium_failure_helper.svg)  
![License](https://img.shields.io/badge/license-MIT-lightgrey)  

Uma GEM de diagnóstico para testes Appium em Ruby, projetada para transformar falhas de automação em **insights acionáveis**. Quando um teste falha por não encontrar um elemento, a ferramenta gera um relatório HTML detalhado, identificando a causa provável e acelerando drasticamente o tempo de depuração.

---

## ✨ Principais Funcionalidades

- **Diagnóstico Inteligente de Falhas:** Identifica automaticamente o tipo de erro (`NoSuchElementError`, `TimeoutError`, falha de asserção ou erro de código Ruby) e gera relatórios personalizados para cada caso.  
- **Análise de Código-Fonte:** Para erros "silenciosos", inspeciona o `stack trace` e extrai o seletor diretamente do código, apontando arquivo e linha exatos.  
- **Comparação Avançada de Atributos:** Compara atributo por atributo (`resource-id`, `text`, etc.) para encontrar o candidato mais provável na tela, evitando análises superficiais.  
- **Relatórios Interativos:** HTML completo com:
  - Screenshot da falha  
  - Diagnóstico claro e sugestões acionáveis  
  - Abas com "Análise Avançada" e "Dump Completo" de todos os elementos da tela  
- **Configuração Flexível:** Personalize caminhos e arquivos de elementos para se adaptar a diferentes estruturas de projeto.

---

## 🚀 Instalação

Adicione ao `Gemfile` do seu projeto de automação:

```ruby
gem 'appium_failure_helper', git: 'URL_DO_SEU_REPOSITORIO_GIT'
```

Depois execute:

```sh
bundle install
```

---

## 🛠️ Uso e Configuração

### 1️⃣ Configuração Inicial (Opcional)

No arquivo de inicialização (`features/support/env.rb`), configure os caminhos de elementos se necessário:

```ruby
require 'appium_failure_helper'

AppiumFailureHelper.configure do |config|
  config.elements_path      = 'features/elements'      # Pasta de elementos
  config.elements_ruby_file = 'elementLists.rb'       # Arquivo Ruby de elementos
end
```

---

### 2️⃣ Enriquecer Exceções (Altamente Recomendado)

Para extrair o máximo de informações de falhas, ajuste seus métodos de busca de elementos:

```ruby
def find(el)
  find_element_with_enriched_error(el)
end

def clickElement(el)
  find_element_with_enriched_error(el).click
end

def waitForElementExist(el, timeout = 10)
  wait = Selenium::WebDriver::Wait.new(timeout: timeout)
  begin
    wait.until { $driver.find_elements(el['tipoBusca'], el['value']).size > 0 }
  rescue Selenium::WebDriver::Error::TimeoutError => e
    raise e.class, "Timeout de #{timeout}s esperando pelo elemento: using \"\#{el['tipoBusca']}\" with value \"\#{el['value']}\""
  end
end

private

def find_element_with_enriched_error(el)
  $driver.find_element(el['tipoBusca'], el['value'])
rescue Selenium::WebDriver::Error::NoSuchElementError => e
  new_exception = e.class.new("using \"\#{el['tipoBusca']}\" with value \"\#{el['value']}\"")
  new_exception.set_backtrace(e.backtrace)
  raise new_exception
end
```

---

### 3️⃣ Integração com Cucumber

No `hooks.rb`, acione a GEM após cada cenário com falha:

```ruby
After do |scenario|
  if scenario.failed? && $driver&.session_id
    AppiumFailureHelper.handler_failure($driver, scenario.exception)
  end
end
```

---

## 📄 Relatório Gerado

A cada falha, a GEM cria uma pasta em `reports_failure/` com:

1. **Relatório Simples:** Para falhas genéricas, mostrando erro, stack trace e diagnóstico direto.  
2. **Relatório Detalhado:** Para problemas de seletor:
   - **Coluna Esquerda:** Elemento com falha, seletores sugeridos e screenshot.  
   - **Coluna Direita:** Abas interativas:
     - **Análise Avançada:** Mostra o candidato mais provável, atributos comparados e sugestões acionáveis.  
     - **Dump Completo:** Lista todos os elementos e possíveis seletores da tela.

---

## 🏛️ Arquitetura

- **Handler:** Captura falhas e aciona o fluxo de análise.  
- **SourceCodeAnalyzer:** Extrai seletores diretamente do código-fonte.  
- **PageAnalyzer:** Analisa o `page_source` e sugere nomes e locators alternativos.  
- **XPathFactory:** Gera estratégias de localização (diretas, combinatórias, parent-based, relativas, parciais, booleanas e posicionais).  
- **ReportGenerator:** Cria relatórios HTML, XML e YAML ricos e interativos.

---

## 🔄 Fluxo Interno da GEM

```
Falha Appium
     │
     ├─► SourceCodeAnalyzer → {selector_type, selector_value}
     │
     └─► PageAnalyzer → [{name, locators, attributes}, ...]
                │
                └─► XPathFactory → [estratégias alternativas]
     │
     ▼
ReportGenerator → HTML / XML / YAML
```

---

## 🤝 Contribuindo

Pull requests e issues são bem-vindos! Abra uma *Issue* para bugs ou sugestões.

---

## 📜 Licença

MIT License
