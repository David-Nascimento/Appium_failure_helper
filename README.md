# Appium Failure Helper

Este módulo Ruby foi projetado para auxiliar na **análise de falhas em testes de automação Appium**. Ao ser invocado, ele captura o estado da aplicação no momento da falha e gera um conjunto de artefatos de diagnóstico, facilitando a identificação da causa raiz do problema e a sugestão de novos localizadores de elementos.

## Funcionalidades Principais

* **Captura de Screenshot:** Salva uma imagem PNG da tela do dispositivo no momento da falha.

* **Captura de Page Source:** Salva o XML do `page_source` completo, representando a hierarquia de elementos da tela.

* **Geração de Sugestões de Elementos:** Analisa o `page_source` e gera um arquivo `.yaml` com sugestões de nomes e caminhos XPath para os elementos visíveis na tela.

## Como Funciona

A lógica central do módulo `AppiumFailureHelper` é acionada por um evento de falha no seu framework de testes (ex: Cucumber `After` hook). A função `handler_failure` executa as seguintes etapas:

1. **Criação de Diretório:** Garante que a pasta `screenshots/` exista para armazenar os artefatos.

2. **Captura de Screenshot e Page Source:** Utiliza o driver do Appium para obter o screenshot e o XML do `page_source`, salvando-os com um timestamp para evitar sobrescrever arquivos.

3. **Análise com Nokogiri:** O XML do `page_source` é parseado utilizando a gem `Nokogiri`.

4. **Processamento de Elementos:** O código itera sobre cada nó do XML (exceto o nó raiz 'hierarchy') e extrai atributos-chave como `resource-id`, `content-desc` e `text`.

5. **Geração de Nomes e XPath:**

   * `suggest_name`: Constrói um nome descritivo para cada elemento, utilizando prefixos comuns (`btn`, `txt`, `input`, etc.) e o valor dos atributos principais.

   * `xpath_generator`: Prioriza atributos mais confiáveis (`resource-id`, `content-desc`, `text`) para gerar um XPath robusto.

6. **Saída Final:** O resultado é um arquivo `.yaml` contendo uma lista formatada de sugestões de locators no formato `["nome_sugerido", "xpath", "caminho_xpath"]`.

## Uso

Para usar este helper, integre-o ao seu framework de testes. Um exemplo comum é utilizá-lo em um hook `After` do Cucumber:

**`features/support/hooks.rb`**

```
require 'caminho/para/o/seu/modulo' # Ajuste o caminho

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