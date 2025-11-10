# lib/appium_failure_helper/source_code_analyzer.rb
module AppiumFailureHelper
  module SourceCodeAnalyzer
    # VERSÃO 4.0: Padrões de Regex corrigidos e muito mais robustos
    PATTERNS = [
      # Padrão 1: find_element(id: 'valor') ou find_element(:id => 'valor')
      # A correção chave é o \s* (espaço opcional) depois do nome do atributo.
      { type: 'id',               regex: /(?:\$driver\.)?find_element\((?:id:\s*|:id\s*=>\s*)['"]([^'"]+)['"]\)/ },
      { type: 'xpath',            regex: /(?:\$driver\.)?find_element\((?:xpath:\s*|:xpath\s*=>\s*)['"]([^'"]+)['"]\)/ },
      { type: 'accessibility_id', regex: /(?:\$driver\.)?find_element\((?:accessibility_id:\s*|:accessibility_id\s*=>\s*)['"]([^'"]+)['"]\)/ },
      { type: 'class_name',       regex: /(?:\$driver\.)?find_element\((?:class_name:\s*|:class_name\s*=>\s*)['"]([^'"]+)['"]\)/ },
      
      # Padrão 2: find_element(:xpath, 'valor')
      { type: 'xpath',            regex: /(?:\$driver\.)?find_element\(:xpath,\s*['"]([^'"]+)['"]\)/ },

      # Padrão 3: Helpers customizados como id('valor') ou xpath('valor')
      { type: 'id',               regex: /(?:\$driver\.)?\s*id\s*\(?['"]([^'"]+)['"]\)?/ },
      { type: 'xpath',            regex: /(?:\$driver\.)?\s*xpath\s*\(?['"]([^'"]+)['"]\)?/ }
    ].freeze

    def self.extract_from_exception(exception)
      # Busca a primeira linha do backtrace que seja um arquivo .rb do projeto
      location = exception.backtrace.find { |line| line.include?('.rb') && !line.include?('gems') }
      return {} unless location

      # Usa o Regex que funciona em Windows e Unix para extrair caminho e linha
      path_match = location.match(/^(.*?):(\d+)(?::in.*)?$/)
      return {} unless path_match

      file_path, line_number = path_match.captures
      return {} unless File.exist?(file_path)

      begin
        # Lê a linha exata onde o erro ocorreu
        error_line = File.readlines(file_path)[line_number.to_i - 1]
        return parse_line_for_locator(error_line)
      rescue
        return {}
      end
    end

    def self.parse_line_for_locator(line)
      PATTERNS.each do |pattern_info|
        match = line.match(pattern_info[:regex])
        if match
          return {
            selector_type: pattern_info[:type].to_s,
            selector_value: match[1],
            analysis_method: "Análise de Código-Fonte"
          }
        end
      end
      {}
    end
  end
end