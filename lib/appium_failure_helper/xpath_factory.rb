module AppiumFailureHelper
  module XPathFactory
    MAX_STRATEGIES = 20

    def self.generate_for_node(node)
      return [] unless node

      # Se vier um Document, usa o root element
      if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Document)
        node = node.root
      end

      # Só continua se for um elemento que suporta atributos
      return [] unless node && node.respond_to?(:attributes) && node.element?

      tag = node.name
      attrs = (node.attributes || {}).transform_values { |a| a.respond_to?(:value) ? a.value : a }

      strategies = []

      add_direct_attribute_strategies(strategies, tag, attrs)
      add_combinatorial_strategies(strategies, tag, attrs)
      add_parent_based_strategies(strategies, tag, node)
      add_relational_strategies(strategies, node)
      add_partial_text_strategies(strategies, tag, attrs)
      add_boolean_strategies(strategies, tag, attrs)
      add_positional_strategies(strategies, node)

      # fallback: se nenhuma estratégia foi criada, garante ao menos o caminho absoluto
      if strategies.empty?
        strategies << { name: "Caminho Absoluto (fallback)", strategy: 'xpath', locator: node.path.to_s, reliability: :baixa }
      end

      strategies.uniq { |s| s[:locator] }.first(MAX_STRATEGIES)
    end

    private

    def self.add_direct_attribute_strategies(strategies, tag, attrs)
      if (id = attrs['resource-id']) && !id.empty?
        strategies << { name: "ID Único (Recomendado)", strategy: 'id', locator: id, reliability: :alta }
      end
      if (text = attrs['text']) && !text.empty?
        strategies << { name: "Texto Exato", strategy: 'xpath', locator: "//#{tag}[@text='#{text}']", reliability: :alta }
      end
      if (desc = attrs['content-desc']) && !desc.empty?
        strategies << { name: "Content Description", strategy: 'xpath', locator: "//#{tag}[@content-desc='#{desc}']", reliability: :alta }
      end
    end

    def self.add_combinatorial_strategies(strategies, tag, attrs)
      valid_attrs = attrs.select { |k, v| %w[text content-desc class package].include?(k) && v && !v.empty? }
      return if valid_attrs.keys.size < 2

      valid_attrs.keys.combination(2).each do |comb|
        locator_parts = comb.map { |k| "@#{k}='#{attrs[k]}'" }.join(' and ')
        attr_names = comb.map(&:capitalize).join(' + ')
        strategies << { name: "Combinação: #{attr_names}", strategy: 'xpath', locator: "//#{tag}[#{locator_parts}]", reliability: :alta }
      end
    end

    def self.add_parent_based_strategies(strategies, tag, node)
      parent = node.parent
      return unless parent
      return if parent.name == 'hierarchy' rescue false

      parent_attrs = {}
      if parent.respond_to?(:attributes) && parent.element?
        parent_attrs = (parent.attributes || {}).transform_values { |a| a.respond_to?(:value) ? a.value : a }
      end

      if (id = parent_attrs['resource-id']) && !id.empty?
        strategies << { name: "Filho de Pai com ID", strategy: 'xpath', locator: "//*[@resource-id='#{id}']//#{tag}", reliability: :alta }
      else
        parent_attrs.each do |k, v|
          next if v.to_s.strip.empty?
          strategies << { name: "Filho de Pai com #{k}", strategy: 'xpath', locator: "//*[@#{k}='#{v}']//#{tag}", reliability: :media }
        end
      end
    end

    def self.add_relational_strategies(strategies, node)
      prev = node.previous_sibling
      if prev && prev.respond_to?(:attributes) && prev.element?
        prev_attrs = (prev.attributes || {}).transform_values { |a| a.respond_to?(:value) ? a.value : a }
        if (text = prev_attrs['text']) && !text.empty?
          strategies << { name: "Relativo ao Irmão Anterior", strategy: 'xpath', locator: "//#{prev.name}[@text='#{text}']/following-sibling::#{node.name}[1]", reliability: :media }
        end
      end
    end

    def self.add_partial_text_strategies(strategies, tag, attrs)
      if (text = attrs['text']) && !text.empty? && text.split.size > 1
        strategies << { name: "Texto Parcial (contains)", strategy: 'xpath', locator: "//#{tag}[contains(@text, '#{text.split.first}')]", reliability: :media }
      end
    end

    def self.add_boolean_strategies(strategies, tag, attrs)
      %w[enabled checked selected].each do |attr|
        if attrs[attr] == 'true'
          strategies << { name: "#{attr.capitalize} é Verdadeiro", strategy: 'xpath', locator: "//#{tag}[@#{attr}='true']", reliability: :media }
        end
      end
    end

    def self.add_positional_strategies(strategies, node)
      index = 1
      begin
        index = node.xpath('preceding-sibling::' + node.name).count + 1
      rescue
        index = 1
      end
      strategies << { name: "Índice na Tela (Frágil)", strategy: 'xpath', locator: "(//#{node.name})[#{index}]", reliability: :baixa }
      strategies << { name: "Caminho Absoluto (Não Recomendado)", strategy: 'xpath', locator: node.path.to_s, reliability: :baixa }
    end
  end
end
