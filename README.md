# Appium Failure Helper

Este módulo Ruby foi projetado para ser uma ferramenta de diagnóstico inteligente para falhas em testes de automação mobile com **Appium**. Ele automatiza a captura de artefatos de depuração e a geração de sugestões de localizadores de elementos, eliminando a necessidade de usar o Appium Inspector.

## Funcionalidades Principais

* **Diagnóstico de Falha Automatizado:** No momento de uma falha, a ferramenta captura automaticamente o estado da aplicação e gera um conjunto de artefatos de depuração.

* **Captura de Artefatos:** Salva um **screenshot** da tela, o **XML completo do `page_source`**, e um relatório de análise em uma pasta com carimbo de data e hora para cada falha.

* **Geração de Localizadores Inteligente:** Percorre a árvore de elementos e gera um relatório YAML com sugestões de XPaths otimizados para cada elemento.

* **Lógica de XPath Otimizada:** Utiliza as melhores práticas para cada plataforma (**Android e iOS**), priorizando os localizadores mais estáveis e combinando atributos para alta especificidade.

* **Tratamento de Dados:** Trunca valores de atributos muito longos para evitar quebras no relatório e garante que não haja elementos duplicados.

* **Sistema de Logging:** Usa a biblioteca padrão `Logger` do Ruby para fornecer feedback detalhado e limpo no console.

* **Múltiplos Relatórios:** Gera dois arquivos YAML: um **focado** no elemento que falhou e um **completo** com todos os elementos da tela.

* **Relatório HTML Interativo:** Cria um relatório HTML visualmente agradável que une o screenshot, o XML e os localizadores sugeridos em uma única página para fácil acesso e análise.

## Como Funciona

O `AppiumFailureHelper` deve ser integrado ao seu framework de testes. Um exemplo comum é utilizá-lo em um hook `After` do Cucumber, passando o objeto de driver do Appium e a exceção do cenário.

**`features/support/hooks.rb`**

```ruby
require 'appium_failure_helper'

After do |scenario|
  if scenario.failed?
    AppiumFailureHelper::Capture.handler_failure(appium_driver, scenario.exception)
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