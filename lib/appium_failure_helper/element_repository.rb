module AppiumFailureHelper
  module ElementRepository
    def self.load_all_from_yaml
      elements_map = {}
      # Procura em todo o diretório de trabalho atual por arquivos .yaml
      glob_path = File.join(Dir.pwd, '**', '*.yaml')
      
      Dir.glob(glob_path).each do |file|
        # Evita ler os próprios relatórios gerados
        next if file.include?('reports_failure')
        
        begin
          data = YAML.load_file(file)
          if data.is_a?(Hash)
            data.each do |key, value|
              if value.is_a?(Hash) && value['tipoBusca'] && value['value']
                elements_map[key] = value
              end
            end
          end
        rescue => e
          Utils.logger.warn("Aviso: Erro ao carregar o arquivo YAML #{file}: #{e.message}")
        end
      end
      elements_map
    end

    # NOVO: Método para verificar a existência de um elemento em um arquivo .rb
    def self.find_in_ruby_file(element_name, path = 'elements/elements.rb')
      return { found: false, path: path, reason: "Arquivo não encontrado" } unless File.exist?(path)

      begin
        content = File.read(path)
        # Regex flexível para encontrar definições como:
        # def nome_do_elemento
        # element :nome_do_elemento
        # element('nome_do_elemento')
        if content.match?(/def #{element_name}|element[ |\(]['|:]#{element_name}/)
          return { found: true, path: path }
        else
          return { found: false, path: path, reason: "Definição não encontrada" }
        end
      rescue => e
        Utils.logger.warn("Aviso: Erro ao ler o arquivo Ruby #{path}: #{e.message}")
        return { found: false, path: path, reason: "Erro de leitura" }
      end
    end
  end
end