# Diagnóstico Inteligente de Falhas Appium

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Gem Version](https://img.shields.io/badge/gem-v1.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Uma ferramenta robusta para diagnosticar falhas em testes automatizados com Appium, transformando erros de `NoSuchElementException` em relatórios interativos e inteligentes. Chega de perder tempo depurando seletores quebrados; deixe que a análise automatizada faça o trabalho pesado por você.

## ✨ Principais Funcionalidades

* **Relatório HTML Interativo:** Gera um relatório visual completo a cada falha, com screenshot, análise detalhada e dump de todos os elementos da tela.
* **Análise de Mapeamento ("De/Para"):** Verifica automaticamente se o elemento que falhou está definido em alguma fonte de dados do projeto, como:
    * **Arquivos `.yaml`** gerados dinamicamente.
    * **Arquivos de elementos Ruby (`.rb`)** customizáveis.
* **Sugestão por Similaridade:** Utiliza o algoritmo de Levenshtein para encontrar elementos na tela que são "parecidos" com o localizador que falhou, sugerindo correções.
* **Altamente Configurável:** Permite que os projetos definam seus próprios caminhos e nomes de arquivos de elementos, tornando a ferramenta totalmente reutilizável.
* **Arquitetura Modular:** O código é limpo, organizado e fácil de estender, seguindo o Princípio da Responsabilidade Única.
* **Suporte Multiplataforma:** A lógica de análise e sugestão funciona tanto para **Android** quanto para **iOS**.

## 🚀 Instalação

Adicione esta linha ao `Gemfile` do seu projeto de automação:

```ruby
gem 'appium_failure_helper' # (ou o nome que você der para a sua gem)
```

E então execute no seu terminal:

```sh
bundle install
```

## ⚙️ Configuração (Opcional)

Para tornar a ferramenta flexível e adaptável a diferentes projetos, você pode configurar os caminhos onde os elementos são buscados. Crie um bloco de configuração no seu arquivo de inicialização (ex: `features/support/env.rb`).

**Se nenhuma configuração for fornecida, a ferramenta usará os valores padrão.**

```ruby
# Em features/support/env.rb

AppiumFailureHelper.configure do |config|
  # Caminho para a pasta que contém os arquivos de elementos.
  # Padrão: 'features/elements'
  config.elements_path = 'caminho/para/sua/pasta/de/elementos'

  # Nome do arquivo principal de elementos Ruby.
  # Padrão: 'elementLists.rb'
  config.elements_ruby_file = 'meu_arquivo_de_elementos.rb'
end
```

### Opções Disponíveis

| Parâmetro             | Descrição                                                                      | Valor Padrão             |
| --------------------- | ------------------------------------------------------------------------------ | ------------------------ |
| `elements_path`       | Path relativo à raiz do projeto para a pasta que contém os arquivos de elementos. | `'features/elements'`    |
| `elements_ruby_file`  | Nome do arquivo Ruby principal que define os elementos dentro da `elements_path`. | `'elementLists.rb'`      |

## 🛠️ Uso no Cucumber

A integração é feita através de um hook `After` no seu ambiente de testes.

**Exemplo completo para `features/support/env.rb`:**

```ruby
# features/support/env.rb

require 'appium_lib'
require 'cucumber'

# 1. Carrega a sua ferramenta
require 'appium_failure_helper'

# 2. (Opcional) Configura os caminhos se forem diferentes do padrão
AppiumFailureHelper.configure do |config|
  config.elements_path = 'features/elements'
  config.elements_ruby_file = 'elementLists.rb'
end

# 3. Hook que executa após cada cenário de teste
After do |scenario|
  # Se o cenário falhou, aciona o seu helper
  if scenario.failed?
    puts "\n--- CENÁRIO FALHOU! ACIONANDO O DIAGNÓSTICO INTELIGENTE ---"
    
    # A chamada ao helper utiliza automaticamente as configurações definidas acima.
    AppiumFailureHelper.handler_failure(@driver, scenario.exception)
    
    puts "--- HELPER FINALIZOU. VERIFIQUE A PASTA 'reports_failure' ---"
  end
end
```

## 📄 Entendendo o Relatório Gerado

Após uma falha, uma nova pasta será criada na raiz do seu projeto: `reports_failure/failure_[timestamp]`. Dentro dela, o arquivo mais importante é o `report_[...].html`.

O relatório HTML é dividido em seções claras para um diagnóstico rápido:

#### Análise de Mapeamento (Bloco Verde/Amarelo)
Informa se o elemento que falhou foi encontrado nos seus arquivos de mapeamento (`.rb` ou `.yaml`).
* **Bloco Verde (Sucesso):** Confirma que o elemento foi encontrado. Isso sugere que a definição está correta, e o problema pode ser de timing ou visibilidade na tela.
* **Bloco Amarelo (Aviso):** Informa que o elemento **não foi encontrado**. Isso geralmente aponta para um erro de digitação no nome do elemento no seu código de teste.

#### Elemento com Falha (Bloco Vermelho)
Mostra exatamente qual `Tipo de Seletor` e `Valor Buscado` o Appium usou quando a falha ocorreu.

#### Screenshot da Falha
Uma imagem exata da tela no momento do erro.

#### Sugestões de Reparo (Análise de Similaridade)
Lista os elementos na tela com localizadores parecidos com o que falhou, com uma pontuação de similaridade. Ideal para corrigir erros de digitação nos seletores.

#### Dump Completo da Página
Uma lista interativa de **todos os elementos** visíveis na tela, com todos os seus possíveis localizadores.

## 🏛️ Arquitetura do Código

O código é modular para facilitar a manutenção e a extensibilidade.

* `configuration.rb`: Classe que armazena as opções configuráveis e seus valores padrão.
* `handler.rb`: O **Maestro**. Orquestra as chamadas para os outros módulos.
* `analyzer.rb`: O **Analista**. Processa a mensagem de erro e calcula a similaridade.
* `element_repository.rb`: O **Repositório**. Encontra e carrega as definições de elementos de arquivos `.yaml` e `.rb` usando os caminhos configurados.
* `page_analyzer.rb`: O **Leitor de Tela**. Processa o XML da página para extrair elementos e sugerir nomes/localizadores.
* `report_generator.rb`: O **Gerador**. Consolida todos os dados e cria os arquivos de relatório.
* `utils.rb`: Funções auxiliares (Logger, etc.).

## 🤝 Como Contribuir

Encontrou um bug ou tem uma ideia para uma nova funcionalidade? Abra uma *Issue* no repositório do projeto. Pull Requests são sempre bem-vindos!

## 📜 Licença

Este projeto é distribuído sob a licença MIT.