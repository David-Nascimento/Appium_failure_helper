# Appium Failure Helper: Diagnóstico Inteligente de Falhas

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Gem Version](https://img.shields.io/badge/gem-v3.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Uma GEM de diagnóstico para testes Appium em Ruby, projetada para transformar falhas de automação em insights acionáveis. Quando um teste falha por não encontrar um elemento, esta ferramenta gera um relatório HTML detalhado, identificando a causa provável do erro e acelerando drasticamente o tempo de depuração.

## ✨ Principais Funcionalidades

* **Diagnóstico por Triagem de Erros:** Identifica inteligentemente o *tipo* de falha (`NoSuchElementError`, `TimeoutError`, `Erro de Código Ruby`, `Falha de Asserção`, etc.) e gera um relatório específico e útil para cada cenário.
* **Análise de Código-Fonte:** Para erros "silenciosos" (onde a mensagem não contém o seletor), a GEM inspeciona o `stack trace` para encontrar o arquivo e a linha exatos do erro, extraindo o seletor diretamente do código-fonte.
* **Análise de Atributos Ponderados:** Em vez de uma simples comparação de strings, a GEM "desmonta" o seletor que falhou e o compara atributo por atributo com os elementos na tela, dando pesos diferentes para `resource-id`, `text`, etc., para encontrar o "candidato mais provável".
* **Relatórios Ricos e Interativos:** Gera um relatório HTML completo com:
    * Screenshot da falha.
    * Diagnóstico claro da causa provável, com sugestões acionáveis.
    * Abas com "Análise Avançada" e um "Dump Completo" de todos os elementos da tela.
* **Altamente Configurável:** Permite a customização de caminhos para se adaptar a diferentes estruturas de projeto.

## 🚀 Instalação

Adicione esta linha ao `Gemfile` do seu projeto de automação:

```ruby
gem 'appium_failure_helper', git: 'URL_DO_SEU_REPOSITORIO_GIT' # Exemplo de instalação via Git
```

E então execute no seu terminal:

```sh
bundle install
```

## 🛠️ Uso e Configuração

A integração ideal envolve 3 passos:

### Passo 1: Configurar a GEM (Opcional)

No seu arquivo de inicialização (ex: `features/support/env.rb`), carregue a GEM e, se necessário, configure os caminhos onde seus elementos estão mapeados. Se nenhuma configuração for fornecida, a ferramenta usará os valores padrão.

```ruby
# features/support/env.rb
require 'appium_failure_helper'

AppiumFailureHelper.configure do |config|
  # Padrão: 'features/elements'
  config.elements_path = 'caminho/para/sua/pasta/de/elementos'

  # Padrão: 'elementLists.rb'
  config.elements_ruby_file = 'meu_arquivo_de_elementos.rb'
end
```

### Passo 2: Enriquecer as Exceções (Altamente Recomendado)

Para que a GEM consiga extrair o máximo de detalhes de uma falha (especialmente de erros genéricos como `TimeoutError` ou `NoSuchElementError` sem detalhes), é crucial que a exceção que ela recebe seja rica em informações. A melhor maneira de garantir isso é ajustar seus métodos de busca de elementos.

Crie ou ajuste um arquivo de helpers (ex: `features/support/appiumCustom.rb`) com a seguinte estrutura:

```ruby
# features/support/appiumCustom.rb

# Métodos públicos que seus Page Objects irão chamar
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
    # Relança o erro com uma mensagem rica que a GEM entende
    new_message = "Timeout de #{timeout}s esperando pelo elemento: using \"#{el['tipoBusca']}\" with value \"#{el['value']}\""
    raise e.class, new_message
  end
end

private # --- Helper Interno ---

# Este método é o coração da solução. Ele captura erros e os enriquece.
def find_element_with_enriched_error(el)
  begin
    return $driver.find_element(el['tipoBusca'], el['value'])
  rescue Selenium::WebDriver::Error::NoSuchElementError => e
    # Cria uma nova mensagem explícita no formato "using... with value..."
    new_message = "using \"#{el['tipoBusca']}\" with value \"#{el['value']}\""
    
    # Recria a exceção original com a nova mensagem.
    new_exception = e.class.new(new_message)
    new_exception.set_backtrace(e.backtrace) # Preserva o stack trace
    raise new_exception
  end
end
```

### Passo 3: Integrar com o Cucumber

Finalmente, no seu `hooks.rb`, acione a GEM no hook `After` em caso de falha.

```ruby
# features/support/hooks.rb

After do |scenario|
  if scenario.failed? && $driver&.session_id
    AppiumFailureHelper.handler_failure($driver, scenario.exception)
  end
end
```

## 📄 O Relatório Gerado

A cada falha, uma nova pasta é criada em `reports_failure/`, contendo o relatório `.html` e outros artefatos. O relatório pode ter dois formatos principais:

1.  **Relatório de Diagnóstico Simples:** Gerado para erros que não são de seletor (ex: falha de conexão, erro de código Ruby, falha de asserção). Ele mostra um diagnóstico direto, a mensagem de erro original e o `stack trace`.

2.  **Relatório Detalhado (para problemas de seletor):**
    * **Coluna da Esquerda:** Mostra o "Elemento com Falha" (extraído da exceção ou do código), "Sugestões Encontradas no Código" e o "Screenshot".
    * **Coluna da Direita:** Contém abas interativas:
        * **Análise Avançada:** Apresenta o "candidato mais provável" encontrado na tela e uma análise comparativa de seus atributos (`resource-id`, `text`, etc.), com uma sugestão acionável.
        * **Dump Completo:** Uma lista de todos os elementos da tela e seus possíveis seletores.

## 🏛️ Arquitetura do Código

A GEM é dividida em módulos com responsabilidades únicas para facilitar a manutenção e a extensibilidade (Handler, Analyzer, ReportGenerator, XPathFactory, etc.).

## 🔄 Fluxo Interno da GEM

Abaixo o fluxo de como os módulos conversam entre si durante o diagnóstico de uma falha:

![Fluxo Interno](img\fluxo_appium_failure_helper.png)

## 🤝 Como Contribuir

Pull Requests são bem-vindos. Para bugs ou sugestões, por favor, abra uma *Issue* no repositório.

## 📜 Licença

Este projeto é distribuído sob a licença MIT.