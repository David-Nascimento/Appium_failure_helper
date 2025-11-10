module AppiumFailureHelper
  module XPathFactory
    MAX_STRATEGIES = 20

    # --- ALTERAÇÃO PRINCIPAL ---
    # O método agora recebe 'tag' e 'attrs', que é tudo o que ele precisa.
    # Ele não depende mais de um nó Nokogiri complexo.
    def self.generate_for_node(tag, attrs)
      strategies = []
      
      # Garante que os argumentos sejam válidos
      tag = (tag || 'element').to_s
      attrs = attrs || {}

      # Executa todas as lógicas de geração
      add_direct_attribute_strategies(strategies, tag, attrs)
      add_combinatorial_strategies(strategies, tag, attrs)
      add_partial_text_strategies(strategies, tag, attrs)
      add_boolean_strategies(strategies, tag, attrs)
      
      # Remove duplicatas e aplica o limite
      strategies.uniq { |s| s[:locator] }.first(MAX_STRATEGIES)
    end

    private

  def self.add_direct_attribute_strategies(strategies, tag, attrs)
    # 1. resource-id (Android)
    if (id = attrs['resource-id']) && !id.empty?
      strategies << {
        name: "ID Único (Recomendado)",
        strategy: 'id',
        locator: id,
        reliability: :alta
      }
    end

    # 2. text exato
    if (text = attrs['text']) && !text.empty?
      strategies << {
        name: "Texto Exato",
        strategy: 'xpath',
        locator: "//#{tag}[@text=#{text.inspect}]",
        reliability: :alta
      }

      # Texto que contém o valor (útil em traduções ou labels dinâmicos)
      if text.split.size > 1
        strategies << {
          name: "Texto Parcial (contains)",
          strategy: 'xpath',
          locator: "//#{tag}[contains(@text, #{text.split.first.inspect})]",
          reliability: :media
        }
      end
    end

    # 3. content-desc (Android)
    if (desc = attrs['content-desc']) && !desc.empty?
      strategies << {
        name: "Content Description",
        strategy: 'accessibility_id',
        locator: desc,
        reliability: :alta
      }

      # fallback via xpath (às vezes accessibility_id falha em híbridos)
      strategies << {
        name: "Content Description (XPath Fallback)",
        strategy: 'xpath',
        locator: "//#{tag}[@content-desc=#{desc.inspect}]",
        reliability: :media
      }
    end

    # 4. name (iOS)
    if (name = attrs['name']) && !name.empty?
      strategies << {
        name: "Name (iOS)",
        strategy: 'name',
        locator: name,
        reliability: :alta
      }
    end

    # 5. label (iOS)
    if (label = attrs['label']) && !label.empty?
      strategies << {
        name: "Label (iOS)",
        strategy: 'xpath',
        locator: "//#{tag}[@label=#{label.inspect}]",
        reliability: :alta
      }
    end

    # 6. class e index (fallback quando não há IDs)
    if (cls = attrs['class']) && !cls.empty? && (index = attrs['index'])
      strategies << {
        name: "Classe + Índice",
        strategy: 'xpath',
        locator: "(//#{tag}[@class=#{cls.inspect}])[#{index.to_i + 1}]",
        reliability: :baixa
      }
    end
  end

  # ----------------------------------------------

  def self.add_combinatorial_strategies(strategies, tag, attrs)
    valid_attrs = attrs.select { |k, v| %w[text content-desc class package label name].include?(k) && v && !v.empty? }
    return if valid_attrs.keys.size < 2

    valid_attrs.keys.combination(2).each do |comb|
      locator_parts = comb.map { |k| "@#{k}=#{attrs[k].inspect}" }.join(' and ')
      attr_names = comb.map(&:capitalize).join(' + ')
      reliability = comb.include?('class') ? :media : :alta

      strategies << {
        name: "Combinação: #{attr_names}",
        strategy: 'xpath',
        locator: "//#{tag}[#{locator_parts}]",
        reliability: reliability
      }
    end
  end

  # ----------------------------------------------

  def self.add_partial_text_strategies(strategies, tag, attrs)
    if (text = attrs['text']) && !text.empty?
      keywords = text.split.select { |t| t.size > 3 } # ignora palavras curtas
      keywords.first(2).each do |kw|
        strategies << {
          name: "Texto Parcial (#{kw})",
          strategy: 'xpath',
          locator: "//#{tag}[contains(@text, #{kw.inspect})]",
          reliability: :media
        }
      end
    end
  end

  # ----------------------------------------------

  def self.add_boolean_strategies(strategies, tag, attrs)
    %w[enabled checked selected clickable focusable focused scrollable long-clickable password].each do |attr|
      if attrs[attr] == 'true'
        reliability = %w[checked selected].include?(attr) ? :alta : :media
        strategies << {
          name: "#{attr.capitalize} é Verdadeiro",
          strategy: 'xpath',
          locator: "//#{tag}[@#{attr}='true']",
          reliability: reliability
        }
      end
    end
  end


    # REMOVIDO: Métodos que dependiam de um nó Nokogiri completo
    # - add_relational_strategies (dependia de .previous_sibling)
    # - add_positional_strategies (dependia de .xpath e .path)
    # - add_parent_based_strategies (dependia de .parent)
    #
    # Estes métodos são inerentemente frágeis e falhavam no nosso cenário de "nó fantasma".
    # As estratégias de atributos diretos e combinatórias são muito mais robustas.
  end
end