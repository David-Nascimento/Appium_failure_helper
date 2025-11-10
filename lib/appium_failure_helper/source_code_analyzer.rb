module AppiumFailureHelper
  module SourceCodeAnalyzer
      # VERSÃO 4.0: Padrões de Regex corrigidos e muito mais robustos
      PATTERNS = [
            # Padrão 1: find_element(id: 'valor') ou find_element(:id => 'valor')
            { type: 'id',               regex: /(?:\$driver\.)?find_element\((?:id:\s*|:id\s*=>\s*)['"]([^'"]+)['"]\)/ },
            { type: 'xpath',            regex: /(?:\$driver\.)?find_element\((?:xpath:\s*|:xpath\s*=>\s*)['"]([^'"]+)['"]\)/ },
            { type: 'accessibility_id', regex: /(?:\$driver\.)?find_element\((?:accessibility_id:\s*|:accessibility_id\s*=>\s*)['"]([^'"]+)['"]\)/ },
            { type: 'class_name',       regex: /(?:\$driver\.)?find_element\((?:class_name:\s*|:class_name\s*=>\s*)['"]([^'"]+)['"]\)/ },

            # Padrão 2: find_element(:xpath, 'valor') — forma comum em Appium
            { type: 'xpath',            regex: /(?:\$driver\.)?find_element\(:xpath,\s*['"]([^'"]+)['"]\)/ },
            { type: 'id',               regex: /(?:\$driver\.)?find_element\(:id,\s*['"]([^'"]+)['"]\)/ },

            # Padrão 3: Helpers customizados — id('valor'), xpath('valor')
            { type: 'id',               regex: /(?:\$driver\.)?\s*id\s*\(?['"]([^'"]+)['"]\)?/ },
            { type: 'xpath',            regex: /(?:\$driver\.)?\s*xpath\s*\(?['"]([^'"]+)['"]\)?/ },

            # Padrão 4: find_elements(...) — capturar listas de elementos
            { type: 'id',               regex: /(?:\$driver\.)?find_elements\((?:id:\s*|:id\s*=>\s*)['"]([^'"]+)['"]\)/ },
            { type: 'xpath',            regex: /(?:\$driver\.)?find_elements\((?:xpath:\s*|:xpath\s*=>\s*)['"]([^'"]+)['"]\)/ },
            { type: 'class_name',       regex: /(?:\$driver\.)?find_elements\((?:class_name:\s*|:class_name\s*=>\s*)['"]([^'"]+)['"]\)/ },

            # Padrão 5: Uso direto do Appium::TouchAction (muito comum em mobile)
            { type: 'tap',              regex: /Appium::TouchAction\.new\.tap\(.*['"]([^'"]+)['"].*\)\.perform/ },

            # Padrão 6: Elementos obtidos antes e usados depois
            # Ex: el = $driver.find_element(:id, 'btn_ok')
            { type: 'id',               regex: /(\w+)\s*=\s*(?:\$driver\.)?find_element\(:id,\s*['"]([^'"]+)['"]\)/ },
            { type: 'xpath',            regex: /(\w+)\s*=\s*(?:\$driver\.)?find_element\(:xpath,\s*['"]([^'"]+)['"]\)/ },

            # Padrão 7: Métodos customizados de Page Object
            # Ex: login_button.click / campo_email.set 'valor'
            { type: 'page_object',      regex: /(\w+)\.(?:click|text|set|send_keys)\b/ },

            # Padrão 8: Capybara (comum em projetos híbridos)
            { type: 'capybara_css',     regex: /find\(['"]([^'"]+)['"]\)/ },
            { type: 'capybara_xpath',   regex: /find\(:xpath,\s*['"]([^'"]+)['"]\)/ },
            { type: 'capybara_id',      regex: /find_by_id\(['"]([^'"]+)['"]\)/ },

            # Padrão 9: By.new(:id, 'valor') — estilo Selenium puro
            { type: 'id',               regex: /By\.new\(:id,\s*['"]([^'"]+)['"]\)/ },
            { type: 'xpath',            regex: /By\.new\(:xpath,\s*['"]([^'"]+)['"]\)/ },

            # Padrão 10: wait.until { ...find_element... }
            { type: 'wait_id',          regex: /wait\.until\s*\{.*find_element\(:id,\s*['"]([^'"]+)['"]\).*?\}/ },
            { type: 'wait_xpath',       regex: /wait\.until\s*\{.*find_element\(:xpath,\s*['"]([^'"]+)['"]\).*?\}/ },

            # Padrão 11: find_element com variáveis dinâmicas
            # Ex: find_element(:xpath, "//button[text()='#{btn_text}']")
            { type: 'xpath_dynamic',    regex: /find_element\(:xpath,\s*["'].*#\{[^}]+\}.*["']\)/ },

            # Padrão 12: chamadas via helper no módulo ScreenObject
            # Ex: element(:btn_login) { id 'login_button' }
            { type: 'screenobject',     regex: /element\(\s*:[^)]+\)\s*\{\s*(id|xpath)\s+['"]([^'"]+)['"]\s*\}/ }
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