# lib/appium_failure_helper/element_repository.rb
module AppiumFailureHelper
  module ElementRepository
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
    
    def self.load_all_from_yaml(base_path)
      elements_map = {}
      glob_path = File.join(base_path, '**', '*.yaml')
      files_found = Dir.glob(glob_path)
      files_found.each do |file|
        next if file.include?('reports_failure')
        begin
          data = YAML.load_file(file)
          if data.is_a?(Hash)
            data.each do |k, v|
              data[k] = normalize_element(v)
            end
            elements_map.merge!(data)
          end
        rescue => e
          Utils.logger.warn("Aviso: Erro ao carregar o arquivo YAML #{file}: #{e.message}")
        end
      end
      elements_map
    end

    def self.normalize_yaml_hash_keys(obj)
      case obj
      when Hash
        result = {}
        obj.each do |k, v|
          k_s = k.to_s
          v_n = normalize_yaml_hash_keys(v)
          # Se v_n é um Hash com chaves :value ou 'valor' -> faça unificação para 'value'
          if v_n.is_a?(Hash)
            if v_n.key?('valor') && !v_n.key?('value')
              v_n['value'] = v_n.delete('valor')
            end
            # também converte :tipoBusca para 'tipoBusca' (string)
          end
          result[k_s] = v_n
        end
        result
      when Array
        obj.map { |el| normalize_yaml_hash_keys(el) }
      else
        obj
      end
    end
  end
end