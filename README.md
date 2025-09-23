# Appium Failure Helper

Este módulo Ruby foi projetado para ser uma ferramenta de diagnóstico inteligente para falhas em testes de automação mobile com **Appium**. Ele automatiza a captura de artefatos de depuração e a geração de sugestões de localizadores de elementos, eliminando a necessidade de usar o Appium Inspector.

## Funcionalidades Principais

* **Análise de Falha Automatizada:** Captura o estado da aplicação no momento da falha.
* **Captura de Artefatos:** Salva um **screenshot** da tela e o **XML completo do `page_source`** em uma pasta dedicada por falha.
* **Geração de Localizadores Inteligente:** Percorre a árvore de elementos e gera um **relatório YAML** com sugestões de XPaths otimizados para cada elemento.
* **Lógica de XPath Otimizada:** Utiliza as melhores práticas para cada plataforma (**Android e iOS**), priorizando os localizadores mais estáveis e combinando atributos para alta especificidade.
* **Organização de Saída:** Cria uma pasta com um carimbo de data/hora para cada falha (`/failure_AAAA_MM_DD_HHMMSS`), mantendo os arquivos organizados.
* **Contexto de Elementos:** O relatório YAML agora inclui o **XPath do elemento pai (`parent_locator`)**, fornecendo contexto crucial para a depuração e construção de Page Objects.

## Como Funciona

A lógica do `AppiumFailureHelper` é ativada por um evento de falha em seu framework de testes (ex: Cucumber `After` hook). O método `handler_failure` executa as seguintes etapas:

1.  Cria um diretório de saída exclusivo.
2.  Captura o screenshot e o `page_source` do driver.
3.  Determina a plataforma do dispositivo a partir das capacidades do driver.
4.  Itera sobre cada nó do `page_source` e, para cada um, chama a lógica de geração de XPath e de nome.
5.  A lógica de XPath utiliza um conjunto de estratégias priorizadas para cada plataforma, como **combinação de atributos** (`@resource-id` e `@text`) e o uso de `starts-with()` para elementos dinâmicos.
6.  Salva um arquivo `.yaml` estruturado, contendo o nome sugerido, o tipo (`xpath`) e o localizador para cada elemento.

## Uso

Para usar este helper, integre-o ao seu framework de testes. Um exemplo comum é utilizá-lo em um hook `After` do Cucumber, passando o objeto de driver do Appium.

**`features/support/hooks.rb`**
```ruby
require 'appium_failure_helper'

After do |scenario|
  if scenario.failed?
    AppiumFailureHelper::Capture.handler_failure(appium_driver)
  end
end

```

**Observação:** O nome da sua variável de driver pode variar. No exemplo, `appium_driver` deve ser o objeto de driver do seu teste.

## Artefatos Gerados

Após uma falha, os seguintes arquivos serão gerados na pasta `screenshots/`:

* `screenshot_20231027_153045.png`

* `page_source_20231027_153045.xml`

* `element_suggestions_20231027_153045.yaml`

O arquivo `.yaml` é um recurso valioso para inspecionar os elementos da tela e atualizar seus localizadores de forma eficiente.