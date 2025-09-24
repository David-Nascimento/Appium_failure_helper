require 'nokogiri'
require 'fileutils'
require 'base64'
require 'yaml'
require 'logger'
require 'did_you_mean'
require 'cgi' # Adicionado para garantir o escape de HTML

module AppiumFailureHelper
  class Capture
    # ... (Constantes PREFIX, MAX_VALUE_LENGTH, @@logger permanecem iguais) ...
    PREFIX = {
      'android.widget.Button' => 'btn', 'android.widget.TextView' => 'txt',
      'android.widget.ImageView' => 'img', 'android.widget.EditText' => 'input',
      'android.widget.CheckBox' => 'chk', 'android.widget.RadioButton' => 'radio',
      'android.widget.Switch' => 'switch', 'android.widget.ViewGroup' => 'group',
      'android.widget.View' => 'view', 'android.widget.FrameLayout' => 'frame',
      'android.widget.LinearLayout' => 'linear', 'android.widget.RelativeLayout' => 'relative',
      'android.widget.ScrollView' => 'scroll', 'android.webkit.WebView' => 'web',
      'android.widget.Spinner' => 'spin', 'XCUIElementTypeButton' => 'btn',
      'XCUIElementTypeStaticText' => 'txt', 'XCUIElementTypeTextField' => 'input',
      'XCUIElementTypeImage' => 'img', 'XCUIElementTypeSwitch' => 'switch',
      'XCUIElementTypeScrollView' => 'scroll', 'XCUIElementTypeOther' => 'elm',
      'XCUIElementTypeCell' => 'cell'
    }.freeze
    MAX_VALUE_LENGTH = 100
    @@logger = nil

    # --- MÉTODO PRINCIPAL (SEM ALTERAÇÕES) ---
    def self.handler_failure(driver, exception)
      begin
        self.setup_logger unless @@logger
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        output_folder = "reports_failure/failure_#{timestamp}"
        FileUtils.mkdir_p(output_folder)
        @@logger.info("Pasta de saída criada: #{output_folder}")
        screenshot_base64 = driver.screenshot_as(:base64)
        page_source = driver.page_source
        File.write("#{output_folder}/page_source_#{timestamp}.xml", page_source)
        doc = Nokogiri::XML(page_source)
        platform = driver.capabilities['platformName']&.downcase || 'unknown'
        failed_element_info = self.extract_info_from_exception(exception)
        local_element_map = self.load_local_element_map
        de_para_result = nil
        logical_name_key = failed_element_info[:selector_value].to_s.gsub(/^#/, '')
        if local_element_map.key?(logical_name_key)
          de_para_result = {
            logical_name: logical_name_key,
            correct_locator: local_element_map[logical_name_key]
          }
        end
        all_elements_suggestions = self.get_all_elements_from_screen(doc, platform)
        similar_elements = self.find_similar_elements(failed_element_info, all_elements_suggestions)
        targeted_report = {
          failed_element: failed_element_info,
          similar_elements: similar_elements,
          de_para_analysis: de_para_result
        }
        File.open("#{output_folder}/failure_analysis_#{timestamp}.yaml", 'w') { |f| f.write(YAML.dump(targeted_report)) }
        File.open("#{output_folder}/all_elements_dump_#{timestamp}.yaml", 'w') { |f| f.write(YAML.dump(all_elements_suggestions)) }
        html_content = self.generate_html_report(targeted_report, all_elements_suggestions, screenshot_base64, platform, timestamp)
        File.write("#{output_folder}/report_#{timestamp}.html", html_content)
        @@logger.info("Relatórios gerados com sucesso em: #{output_folder}")
      rescue => e
        @@logger.error("Erro ao capturar detalhes da falha: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    private

    def self.load_local_element_map
      elements_map = {}
      glob_path = File.join(Dir.pwd, 'features', 'elements', '**', '*.yaml')
      Dir.glob(glob_path).each do |file|
        begin
          data = YAML.load_file(file)
          if data.is_a?(Hash)
            data.each do |key, value|
              if value.is_a?(Hash) && value['tipoBusca'] && value['valor']
                elements_map[key] = value
              end
            end
          end
        rescue => e
          @@logger.warn("Aviso: Erro ao carregar o arquivo de elementos #{file}: #{e.message}") if @@logger
        end
      end
      elements_map
    end

    def self.setup_logger
        @@logger = Logger.new(STDOUT)
        @@logger.level = Logger::INFO
        @@logger.formatter = proc { |severity, datetime, progname, msg| "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n" }
    end

    def self.extract_info_from_exception(exception)
        message = exception.message
        info = {}
        patterns = [
          /element with locator ['"]?(#?\w+)['"]?/i,
          /(?:could not be found|cannot find element) using (.+?)=['"]?([^'"]+)['"]?/i,
          /no such element: Unable to locate element: {"method":"([^"]+)","selector":"([^"]+)"}/i,
          /(?:with the resource-id|with the accessibility-id) ['"]?(.+?)['"]?/i
        ]
        patterns.each do |pattern|
            match = message.match(pattern)
            if match
                info[:selector_value] = match.captures.last.strip.gsub(/['"]/, '')
                info[:selector_type] = match.captures.size > 1 ? match.captures[0].strip.gsub(/['"]/, '') : 'id' # Padroniza para 'id'
                return info
            end
        end
        info
    end
    
   
    def self.find_similar_elements(failed_element_info, all_page_suggestions)
      failed_locator_value = failed_element_info[:selector_value]
      failed_locator_type = failed_element_info[:selector_type]
      return [] unless failed_locator_value && failed_locator_type

      # Padroniza os tipos de localizador (ex: 'resource-id' vira 'id')
      normalized_failed_type = failed_locator_type.downcase.include?('id') ? 'id' : failed_locator_type

      cleaned_failed_locator = failed_locator_value.to_s.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
      similarities = []

      all_page_suggestions.each do |suggestion|
        # Procura por um localizador na sugestão que tenha a MESMA ESTRATÉGIA do localizador que falhou
        candidate_locator = suggestion[:locators].find { |loc| loc[:strategy] == normalized_failed_type }
        next unless candidate_locator
        
        cleaned_candidate_locator = candidate_locator[:locator].gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
        distance = DidYouMean::Levenshtein.distance(cleaned_failed_locator, cleaned_candidate_locator)
        max_len = [cleaned_failed_locator.length, cleaned_candidate_locator.length].max
        next if max_len.zero?
        
        similarity_score = 1.0 - (distance.to_f / max_len)
        if similarity_score > 0.8 # Aumenta o limiar para maior precisão
          similarities << { name: suggestion[:name], locators: suggestion[:locators], score: similarity_score }
        end
      end
      similarities.sort_by { |s| -s[:score] }.first(5)
    end
    
    # ... (get_all_elements_from_screen, truncate, suggest_name permanecem iguais) ...
    def self.get_all_elements_from_screen(doc, platform)
        seen_elements = {}
        all_elements_suggestions = []
        doc.xpath('//*').each do |node|
            next if ['hierarchy', 'AppiumAUT'].include?(node.name)
            attrs = node.attributes.transform_values(&:value)
            unique_key = "#{node.name}|#{attrs['resource-id']}|#{attrs['content-desc']}|#{attrs['text']}"
            unless seen_elements[unique_key]
                name = self.suggest_name(node.name, attrs)
                locators = self.xpath_generator(node.name, attrs, platform)
                all_elements_suggestions << { name: name, locators: locators }
                seen_elements[unique_key] = true
            end
        end
        all_elements_suggestions
    end

    def self.truncate(value)
      return value unless value.is_a?(String)
      value.size > MAX_VALUE_LENGTH ? "#{value[0...MAX_VALUE_LENGTH]}..." : value
    end

    def self.suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'
      name_base = nil
      
      priority_attrs = if tag.start_with?('XCUIElementType')
                        ['name', 'label', 'value']
                      else
                        ['content-desc', 'text', 'resource-id']
                      end

      priority_attrs.each do |attr_key|
        value = attrs[attr_key]
        if value.is_a?(String) && !value.empty?
          name_base = value
          break
        end
      end
      
      # Se nenhum atributo de prioridade for encontrado, usa o nome da classe.
      name_base ||= type.gsub('XCUIElementType', '') # Remove o prefixo longo do iOS
      
      truncated_name = truncate(name_base)
      sanitized_name = truncated_name.gsub(/[^a-zA-Z0-9\s]/, ' ').split.map(&:capitalize).join
      
      "#{pfx}#{sanitized_name}"
    end

    def self.xpath_generator(tag, attrs, platform)
      case platform
      when 'android' then self.generate_android_xpaths(tag, attrs)
      when 'ios' then self.generate_ios_xpaths(tag, attrs)
      else self.generate_unknown_xpaths(tag, attrs)
      end
    end

    def self.generate_android_xpaths(tag, attrs)
      locators = []
      if attrs['resource-id'] && !attrs['resource-id'].empty?
        # CORREÇÃO: A estratégia para resource-id é 'id', e o valor é o próprio ID.
        locators << { strategy: 'id', locator: attrs['resource-id'] }
      end
      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'xpath', locator: "//#{tag}[@text=\"#{truncate(attrs['text'])}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'xpath_desc', locator: "//#{tag}[@content-desc=\"#{truncate(attrs['content-desc'])}\"]" }
      end
      locators
    end

    def self.generate_ios_xpaths(tag, attrs)
      locators = []
      if attrs['name'] && !attrs['name'].empty?
        # CORREÇÃO: A estratégia para 'name' no iOS é 'name', e o valor é o próprio nome.
        locators << { strategy: 'name', locator: attrs['name'] }
      end
      if attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'xpath', locator: "//#{tag}[@label=\"#{truncate(attrs['label'])}\"]" }
      end
      locators
    end
    
    def self.generate_unknown_xpaths(tag, attrs)
        locators = []
        attrs.each { |key, value| locators << { strategy: key.to_s, locator: "//#{tag}[@#{key}=\"#{truncate(value)}\"]" } if value.is_a?(String) && !value.empty? }
        locators
    end
    
    def self.generate_html_report(targeted_report, all_suggestions, screenshot_base64, platform, timestamp)
      # Lambdas para gerar partes do HTML
      locators_html = lambda do |locators|
        locators.map { |loc| "<li class='flex justify-between items-center bg-gray-50 p-2 rounded-md mb-1 text-xs font-mono'><span class='font-bold text-indigo-600'>#{CGI.escapeHTML(loc[:strategy].upcase.gsub('_', ' '))}:</span><span class='text-gray-700 ml-2 overflow-auto max-w-[70%]'>#{CGI.escapeHTML(loc[:locator])}</span></li>" }.join
      end

      all_elements_html = lambda do |elements|
        elements.map { |el| "<details class='border-b border-gray-200 py-3'><summary class='font-semibold text-sm text-gray-800 cursor-pointer'>#{CGI.escapeHTML(el[:name])}</summary><ul class='text-xs space-y-1 mt-2'>#{locators_html.call(el[:locators])}</ul></details>" }.join
      end

      # Prepara o conteúdo dinâmico
      failed_info = targeted_report[:failed_element]
      similar_elements = targeted_report[:similar_elements]
      de_para_analysis = targeted_report[:de_para_analysis]

      # Bloco de HTML para a análise "De/Para"
      de_para_html = ""
      if de_para_analysis
        de_para_html = <<~HTML
          <div class="bg-green-50 border border-green-200 p-4 rounded-lg shadow-md mb-6">
            <h3 class="text-lg font-bold text-green-800 mb-2">Análise de Mapeamento (De/Para)</h3>
            <p class="text-sm text-gray-700 mb-1">O nome lógico <strong class="font-mono bg-gray-200 px-1 rounded">#{CGI.escapeHTML(de_para_analysis[:logical_name])}</strong> foi encontrado nos seus arquivos locais!</p>
            <p class="text-sm text-gray-700">O localizador correto definido é:</p>
            <div class="font-mono text-xs bg-green-100 p-2 mt-2 rounded">
              <span class="font-bold">#{CGI.escapeHTML(de_para_analysis[:correct_locator]['tipoBusca'].upcase)}:</span>
              <span class="break-all">#{CGI.escapeHTML(de_para_analysis[:correct_locator]['valor'])}</span>
            </div>
          </div>
        HTML
      end

      similar_elements_content = similar_elements.empty? ? "<p class='text-gray-500'>Nenhuma alternativa semelhante foi encontrada na tela atual.</p>" : similar_elements.map { |el|
        score_percent = (el[:score] * 100).round(1)
        "<div class='border border-indigo-100 p-3 rounded-lg bg-indigo-50'><p class='font-bold text-indigo-800 mb-2'>#{CGI.escapeHTML(el[:name])} <span class='text-xs font-normal text-green-600 bg-green-100 rounded-full px-2 py-1'>Similaridade: #{score_percent}%</span></p><ul>#{locators_html.call(el[:locators])}</ul></div>"
      }.join

      failed_info_content = if failed_info && failed_info[:selector_value]
        "<p class='text-sm text-gray-700 font-medium mb-2'>Tipo de Seletor: <span class='font-mono text-xs bg-red-100 p-1 rounded'>#{CGI.escapeHTML(failed_info[:selector_type].to_s)}</span></p><p class='text-sm text-gray-700 font-medium'>Valor Buscado: <span class='font-mono text-xs bg-red-100 p-1 rounded break-all'>#{CGI.escapeHTML(failed_info[:selector_value].to_s)}</span></p>"
      else
        "<p class='text-sm text-gray-500'>O localizador exato não pôde ser extraído da mensagem de erro.</p>"
      end

      # Template HTML completo
      <<~HTML_REPORT
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Relatório de Falha Appium - #{timestamp}</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <style> body { font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto; } .tab-content { display: none; } .tab-content.active { display: block; } .tab-button.active { background-color: #4f46e5; color: white; } </style>
        </head>
        <body class="bg-gray-50 p-8">
          <div class="max-w-7xl mx-auto">
            <header class="mb-8 pb-4 border-b border-gray-300">
              <h1 class="text-3xl font-bold text-gray-800">Diagnóstico de Falha Automatizada</h1>
              <p class="text-sm text-gray-500">Relatório gerado em: #{timestamp} | Plataforma: #{platform.upcase}</p>
            </header>
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
              <div class="lg:col-span-1">
                #{de_para_html}
                <div class="bg-white p-4 rounded-lg shadow-xl mb-6 border border-red-200">
                  <h2 class="text-xl font-bold text-red-600 mb-4">Elemento com Falha</h2>
                  #{failed_info_content}
                </div>
                <div class="bg-white p-4 rounded-lg shadow-xl">
                  <h2 class="text-xl font-bold text-gray-800 mb-4">Screenshot da Falha</h2>
                  <img src="data:image/png;base64,#{screenshot_base64}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
                </div>
              </div>
              <div class="lg:col-span-2">
                <div class="bg-white rounded-lg shadow-xl">
                  <div class="flex border-b border-gray-200">
                    <button class="tab-button active px-4 py-3 text-sm font-medium rounded-tl-lg" data-tab="similar">Sugestões de Reparo (#{similar_elements.size})</button>
                    <button class="tab-button px-4 py-3 text-sm font-medium text-gray-600" data-tab="all">Dump Completo da Página (#{all_suggestions.size} Elementos)</button>
                  </div>
                  <div class="p-6">
                    <div id="similar" class="tab-content active">
                      <h3 class="text-lg font-semibold text-indigo-700 mb-4">Elementos Semelhantes (Alternativas para o Localizador Falho)</h3>
                      <div class="space-y-4">#{similar_elements_content}</div>
                    </div>
                    <div id="all" class="tab-content">
                      <h3 class="text-lg font-semibold text-indigo-700 mb-4">Dump de Todos os Elementos da Tela</h3>
                      <div class="max-h-[600px] overflow-y-auto space-y-2">#{all_elements_html.call(all_suggestions)}</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <script>
            document.querySelectorAll('.tab-button').forEach(tab => {
              tab.addEventListener('click', () => {
                const target = tab.getAttribute('data-tab');
                document.querySelectorAll('.tab-button').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                tab.classList.add('active');
                document.getElementById(target).classList.add('active');
              });
            });
          </script>
        </body>
        </html>
      HTML_REPORT
    end
  end
end