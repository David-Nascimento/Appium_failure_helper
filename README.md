# Appium Failure Helper: Diagnóstico Inteligente de Falhas

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Gem Version](https://badge.fury.io/rb/appium_failure_helper.svg)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Uma GEM de diagnóstico para testes Appium em Ruby, projetada para transformar falhas de automação em **insights acionáveis**. Quando um teste falha por não encontrar um elemento, esta ferramenta gera um relatório HTML detalhado e interativo, identificando a causa provável e acelerando drasticamente o tempo de depuração.

---

## Principais Funcionalidades

- **Triagem Inteligente de Erros:** Identifica automaticamente o *tipo* de falha (`NoSuchElementError`, `TimeoutError`, `NoMethodError`, etc.) e decide se deve gerar um relatório de análise profunda ou um diagnóstico simples.
- **Análise de Código-Fonte:** Para erros "silenciosos" (onde a mensagem não contém o seletor), inspeciona o `stack trace` para encontrar o arquivo e a linha exatos do erro, extraindo o seletor diretamente do código.
- **Análise Avançada (Atributos Ponderados):** O "coração" da GEM. Em vez de uma simples comparação de strings, ela "desmonta" o seletor que falhou e o compara, atributo por atributo, com todos os elementos na tela. Ela dá pesos diferentes para `resource-id`, `text`, etc., para encontrar o "candidato mais provável" na tela.
- **Fábrica de Estratégias de Reparo:** Após identificar o "candidato mais provável", a `XPathFactory` gera uma lista rica (até 20) de seletores alternativos e robustos para *aquele* elemento, exibidos em um carrossel paginado.
- **Busca Reversa no Código:** A ferramenta varre seus arquivos `.rb` para encontrar definições de seletores que são parecidas com o que falhou, exibindo o trecho de código e o arquivo.
- **Relatórios Ricos e Interativos:** Gera um relatório HTML completo com:
  - Screenshot da falha.
  - Diagnóstico claro e sugestões acionáveis.
  - Abas com "Análise Avançada", "Estratégias de Reparo" e "Dump Completo" de todos os elementos da tela.
- **Configuração Flexível:** Permite a customização de caminhos de arquivos de elementos.

---

## Instalação

Adicione ao `Gemfile` do seu projeto de automação:

```ruby
gem 'appium_failure_helper', git: 'URL_DO_SEU_REPOSITORIO_GIT'
```

Depois execute:

```sh
bundle install
```

---

## Uso e Configuração

A integração é feita em 3 etapas para garantir máxima eficiência.

### 1. Configuração Inicial (Opcional)

No arquivo de inicialização (`features/support/env.rb`), carregue a GEM e, opcionalmente, configure os caminhos de elementos se eles forem diferentes do padrão.

```ruby
require 'appium_failure_helper'

AppiumFailureHelper.configure do |config|
  # Caminho para a pasta que contém os arquivos de elementos.
  # Padrão: 'features/elements'
  config.elements_path = 'features/elements'

  # Nome do arquivo Ruby principal que define os elementos.
  # Padrão: 'elementLists.rb'
  config.elements_ruby_file = 'elementLists.rb'
end
```

### 2. Enriquecer Exceções (Etapa Crucial)

Para que a GEM consiga analisar erros "silenciosos" (como `TimeoutError` ou falhas dentro de helpers), é **essencial** que seu framework de automação "enriqueça" a exceção antes de ela ser lançada.

Ajuste seus métodos de busca de elementos (ex: em `features/support/appiumCustom.rb`) para que eles capturem a falha e a relancem com uma mensagem detalhada no formato `using "tipo" with value "valor"`.

```ruby
# features/support/appiumCustom.rb

# --- MÉTODO DE ESPERA ENRIQUECIDO ---
def waitForElementExist(el, timeout = 30)
  wait = Selenium::WebDriver::Wait.new(timeout: timeout)
  begin
    wait.until { $driver.find_elements(el['tipoBusca'], el['value']).size > 0 }
  rescue Selenium::WebDriver::Error::TimeoutError => e
    # CRUCIAL: Relança o erro com uma mensagem explícita que a GEM entende.
    new_message = "Timeout de #{timeout}s esperando pelo elemento: using \"#{el['tipoBusca']}\" with value \"#{el['value']}\""
    new_exception = e.class.new(new_message)
    new_exception.set_backtrace(e.backtrace) # Preserva o stack trace
    raise new_exception
  end
end

# --- MÉTODO DE BUSCA ENRIQUECIDO ---
def find(el)
  find_element_with_enriched_error(el)
end

def clickElement(el)
  find_element_with_enriched_error(el).click
end

private

# Helper central que enriquece erros de 'find_element'
def find_element_with_enriched_error(el)
  begin
    return $driver.find_element(el['tipoBusca'], el['value'])
  rescue Selenium::WebDriver::Error::NoSuchElementError => e
    new_message = "using \"#{el['tipoBusca']}\" with value \"#{el['value']}\""
    new_exception = e.class.new(new_message)
    new_exception.set_backtrace(e.backtrace)
    raise new_exception
  end
end
```

### 3. Integração com Cucumber

No `hooks.rb`, acione a GEM após cada cenário com falha:

```ruby
# features/support/hooks.rb

After do |scenario|
  if scenario.failed? && $driver&.session_id
    AppiumFailureHelper.handler_failure($driver, scenario.exception)
  end
end
```

---

## 4. Integração com CI/CD (Jenkins)

Você pode configurar sua GEM para publicar os relatórios HTML diretamente no painel do Jenkins. Isso dá visibilidade imediata para toda a equipe sobre a causa de um build quebrado, sem a necessidade de acessar logs ou baixar arquivos.

➡️ **[Guia Completo de Integração com Jenkins](ci/CI_INTEGRATION.md)**

## O Relatório Gerado

A cada falha, a GEM cria uma pasta em `reports_failure/` com:

1.  **Relatório Simples:** Para falhas não relacionadas a seletores (ex: erro de código Ruby, falha de conexão). Mostra um diagnóstico direto, o erro original, o stack trace e o screenshot.
2.  **Relatório Detalhado:** Gerado quando um problema de seletor é identificado.
    * **Coluna Esquerda:**
        * `Elemento com Falha`: O seletor exato que falhou (extraído da mensagem ou do código).
        * `Sugestões Encontradas no Código`: (Opcional) Sugestões de seletores parecidos encontrados no seu código-fonte.
        * `Screenshot da Falha`: A imagem da tela no momento do erro.
    * **Coluna Direita (Abas):**
        * `Análise Avançada`: O "candidato mais provável" encontrado na tela, com uma análise comparativa de seus atributos (`resource-id`, `text`, etc.) e uma sugestão acionável.
        * `Estratégias de Reparo`: Um carrossel paginado com até 20 estratégias de localização (XPaths, IDs) geradas pela `XPathFactory` para o candidato encontrado.
        * `Dump Completo`: A lista de todos os elementos visíveis na tela.

---

## Arquitetura

* **Handler:** O maestro que orquestra todo o fluxo de análise.
* **Analyzer:** O analista. Faz a triagem do erro e executa a "Análise Avançada" por atributos ponderados.
* **SourceCodeAnalyzer:** Especialista em ler o `stack trace` para extrair seletores de dentro do código-fonte.
* **CodeSearcher:** O detetive. Faz a busca reversa por strings de seletores similares em todo o projeto.
* **ElementRepository:** O repositório que carrega os mapas de elementos de arquivos `.rb` e `.yaml` (De/Para).
* **PageAnalyzer:** O leitor de tela. Processa o XML da página para extrair todos os elementos e seus atributos.
* **XPathFactory:** A fábrica que gera dezenas de estratégias de XPath (diretas, combinatórias, relacionais, etc.).
* **ReportGenerator:** O construtor. Renderiza os relatórios HTML (detalhado ou simples) com base nos dados da análise.
* **Configuration:** Gerencia as configurações da GEM.
* **Utils:** Funções auxiliares (Logger, etc.).

---

## 🤝 Contribuindo

Pull requests e issues são bem-vindos! Abra uma *Issue* para bugs ou sugestões.

---

## 📜 Licença

MIT License