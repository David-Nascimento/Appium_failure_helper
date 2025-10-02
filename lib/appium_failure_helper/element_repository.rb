# lib/appium_failure_helper/element_repository.rb
module AppiumFailureHelper
  module ElementRepository
    ELEMENTS = {}
    def self.load_all
      config = AppiumFailureHelper.configuration
      base_path = config.elements_path
      elements_map = load_from_ruby_file(base_path, config.elements_ruby_file)
      elements_map.merge!(load_all_from_yaml(base_path))
      Utils.logger.info("Mapa de elementos carregado da pasta '#{base_path}'. Total: #{elements_map.size}.")
      elements_map
    end

    private

    def self.load_from_ruby_file(base_path, filename)
      map = {}
      file_path = File.join(base_path, filename)
      return map unless File.exist?(file_path)
      begin
        require File.expand_path(file_path)
        instance = OnboardingElementLists.new
        unless instance.respond_to?(:elements)
          Utils.logger.warn("AVISO: A classe #{instance.class} não expõe um `attr_reader :elements`.")
          return map
        end
        instance.elements.each do |key, value|
          valor = value[1]
          if valor.is_a?(Hash)
            valor_final = valor['valor'] || valor['value'] || valor
          else
            valor_final = valor
          end
          map[key.to_s] = { 'tipoBusca' => value[0], 'valor' => valor_final }
        end
      rescue => e
        Utils.logger.warn("AVISO: Erro ao processar o arquivo Ruby #{file_path}: #{e.message}")
      end
      map
    end
    
    def self.load_all_from_yaml(dir_path = 'features/elements')
      Dir.glob("#{dir_path}/*.yaml").each do |file|
        begin
          yaml_data = YAML.load_file(file)
          yaml_data.each do |key, value|
            ELEMENTS[key.to_sym] = normalize_element(value)
          end
        rescue => e
          Utils.logger.warn("Aviso: Erro ao carregar o arquivo YAML #{file}: #{e.message}")
        end
      end
      Utils.logger.info("Número de elementos carregados: #{ELEMENTS.size}")
      ELEMENTS
    end

    def self.normalize_element(element_hash)
      # Ajuste para garantir keys simbólicas e paths padrão
      element_hash.transform_keys(&:to_sym).tap do |h|
        h[:selector_type] ||= h[:type] || 'unknown'
        h[:selector_value] ||= h[:value] || 'unknown'
      end
    end
  end
end