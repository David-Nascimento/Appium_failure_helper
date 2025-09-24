module AppiumFailureHelper
  module ElementRepository
  
    def self.load_all
      elements_map = load_from_ruby_file
      elements_map.merge!(load_all_from_yaml)
      elements_map
    end

    private

    def self.load_from_ruby_file
      map = {}
      # ALTERADO: Lê os caminhos a partir da configuração central.
      config = AppiumFailureHelper.configuration
      file_path = File.join(Dir.pwd, config.elements_path, config.elements_ruby_file)
      
      return map unless File.exist?(file_path)

      # ... (o resto do método continua igual)
      begin
        require file_path
        instance = OnboardingElementLists.new
        unless instance.respond_to?(:elements)
          Utils.logger.warn("AVISO: A classe OnboardingElementLists não expõe um `attr_reader :elements`.")
          return map
        end
        instance.elements.each do |key, value|
          map[key.to_s] = { 'tipoBusca' => value[0], 'valor' => value[1] }
        end
      rescue => e
        Utils.logger.warn("AVISO: Erro ao processar o arquivo #{file_path}: #{e.message}")
      end
      
      map
    end
    
    def self.load_all_from_yaml
      elements_map = {}
      # ALTERADO: Lê o caminho base da configuração central.
      config = AppiumFailureHelper.configuration
      glob_path = File.join(Dir.pwd, config.elements_path, '**', '*.yaml')
      
      Dir.glob(glob_path).each do |file|
        # ... (o resto do método continua igual) ...
        next if file.include?('reports_failure')
        begin
          data = YAML.load_file(file)
          elements_map.merge!(data) if data.is_a?(Hash)
        rescue => e
          Utils.logger.warn("Aviso: Erro ao carregar o arquivo YAML #{file}: #{e.message}")
        end
      end
      elements_map
    end
  end
end