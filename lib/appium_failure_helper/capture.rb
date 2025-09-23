require 'nokogiri'
require 'fileutils'
require 'base64'
require 'yaml'
require 'logger'

module AppiumFailureHelper
  class Capture
    PREFIX = {
      'android.widget.Button' => 'btn',
      'android.widget.TextView' => 'txt',
      'android.widget.ImageView' => 'img',
      'android.widget.EditText' => 'input',
      'android.widget.CheckBox' => 'chk',
      'android.widget.RadioButton' => 'radio',
      'android.widget.Switch' => 'switch',
      'android.widget.ViewGroup' => 'group',
      'android.widget.View' => 'view',
      'android.widget.FrameLayout' => 'frame',
      'android.widget.LinearLayout' => 'linear',
      'android.widget.RelativeLayout' => 'relative',
      'android.widget.ScrollView' => 'scroll',
      'android.webkit.WebView' => 'web',
      'android.widget.Spinner' => 'spin',
      'XCUIElementTypeButton' => 'btn',
      'XCUIElementTypeStaticText' => 'txt',
      'XCUIElementTypeTextField' => 'input',
      'XCUIElementTypeImage' => 'img',
      'XCUIElementTypeSwitch' => 'switch',
      'XCUIElementTypeScrollView' => 'scroll',
      'XCUIElementTypeOther' => 'elm',
      'XCUIElementTypeCell' => 'cell',
    }.freeze
    
    MAX_VALUE_LENGTH = 100
    @@logger = nil

    def self.handler_failure(driver, exception)
      begin
        self.setup_logger unless @@logger
        
        # Remove a pasta reports_failure ao iniciar uma nova execução
        FileUtils.rm_rf("reports_failure")
        @@logger.info("Pasta 'reports_failure' removida para uma nova execução.")
        
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        output_folder = "reports_failure/failure_#{timestamp}"
        
        FileUtils.mkdir_p(output_folder)
        @@logger.info("Pasta de saída criada: #{output_folder}")
        
        # Captura o Base64 e salva o PNG
        screenshot_base64 = driver.screenshot_as(:base64)
        screenshot_path = "#{output_folder}/screenshot_#{timestamp}.png"
        File.open(screenshot_path, 'wb') do |f|
          f.write(Base64.decode64(screenshot_base64))
        end
        @@logger.info("Screenshot salvo em #{screenshot_path}")

        page_source = driver.page_source
        xml_path = "#{output_folder}/page_source_#{timestamp}.xml"
        File.write(xml_path, page_source)
        @@logger.info("Page source salvo em #{xml_path}")

        doc = Nokogiri::XML(page_source)
        platform = driver.capabilities['platformName']&.downcase || 'unknown'

        failed_element_info = self.extract_info_from_exception(exception)

        # --- Processamento de todos os elementos ---
        seen_elements = {}
        all_elements_suggestions = []
        doc.xpath('//*').each do |node|
          next if node.name == 'hierarchy'
          attrs = node.attributes.transform_values(&:value)
          
          unique_key = "#{node.name}|#{attrs['resource-id'].to_s}|#{attrs['content-desc'].to_s}|#{attrs['text'].to_s}"
          
          unless seen_elements[unique_key]
            name = self.suggest_name(node.name, attrs)
            locators = self.xpath_generator(node.name, attrs, platform)
            
            all_elements_suggestions << { name: name, locators: locators }
            seen_elements[unique_key] = true
          end
        end

        # --- Geração do Relatório FOCADO (1) ---
        targeted_report = {
          failed_element: failed_element_info,
          similar_elements: [],
        }

        if failed_element_info && failed_element_info[:selector_value]
          targeted_report[:similar_elements] = self.find_similar_elements(doc, failed_element_info, platform)
        end
        
        targeted_yaml_path = "#{output_folder}/failure_analysis_#{timestamp}.yaml"
        File.open(targeted_yaml_path, 'w') do |f|
          f.write(YAML.dump(targeted_report))
        end
        @@logger.info("Análise direcionada salva em #{targeted_yaml_path}")

        # --- Geração do Relatório COMPLETO (2) ---
        full_dump_yaml_path = "#{output_folder}/all_elements_dump_#{timestamp}.yaml"
        File.open(full_dump_yaml_path, 'w') do |f|
          f.write(YAML.dump(all_elements_suggestions))
        end
        @@logger.info("Dump completo da página salvo em #{full_dump_yaml_path}")

        # --- Geração do Relatório HTML (3) ---
        html_report_path = "#{output_folder}/report_#{timestamp}.html"
        html_content = self.generate_html_report(targeted_report, all_elements_suggestions, screenshot_base64, platform, timestamp)
        File.write(html_report_path, html_content)
        @@logger.info("Relatório HTML completo salvo em #{html_report_path}")


      rescue => e
        @@logger.error("Erro ao capturar detalhes da falha: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    private
    
    def self.setup_logger
      @@logger = Logger.new(STDOUT)
      @@logger.level = Logger::INFO
      @@logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
      end
    end

    # --- LÓGICA DE GERAÇÃO DE HTML ---
    def self.generate_html_report(targeted_report, all_suggestions, screenshot_base64, platform, timestamp)
      
      # Helper para formatar localizadores
      locators_html = lambda do |locators|
        locators.map do |loc|
          "<li class='flex justify-between items-center bg-gray-50 p-2 rounded-md mb-1 text-xs font-mono'><span class='font-bold text-indigo-600'>#{loc[:strategy].upcase.gsub('_', ' ')}:</span><span class='text-gray-700 ml-2 overflow-auto max-w-[70%]'>#{loc[:locator]}</span></li>"
        end.join
      end

      # Helper para criar a lista de todos os elementos
      all_elements_html = lambda do |elements|
        elements.map do |el|
          "<div class='border-b border-gray-200 py-3'><p class='font-semibold text-sm text-gray-800 mb-1'>#{el[:name]}</p><ul class='text-xs space-y-1'>#{locators_html.call(el[:locators])}</ul></div>"
        end.join
      end

      # Template HTML usando um heredoc
      <<~HTML_REPORT
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Relatório de Falha Appium - #{timestamp}</title>
            <script src="https://cdn.tailwindcss.com"></script>
            <style>
                body { font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif; }
                .tab-content { display: none; }
                .tab-content.active { display: block; }
                .tab-button.active { background-color: #4f46e5; color: white; }
                .tab-button:not(.active):hover { background-color: #e0e7ff; }
            </style>
        </head>
        <body class="bg-gray-50 p-8">
            <div class="max-w-7xl mx-auto">
                <header class="mb-8 pb-4 border-b border-gray-300">
                    <h1 class="text-3xl font-bold text-gray-800">Diagnóstico de Falha Automatizada</h1>
                    <p class="text-sm text-gray-500">Relatório gerado em: #{timestamp} | Plataforma: #{platform.upcase}</p>
                </header>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
                    <div class="lg:col-span-1">
                        <div class="bg-white p-4 rounded-lg shadow-xl mb-6 border border-red-200">
                            <h2 class="text-xl font-bold text-red-600 mb-4">Elemento com Falha</h2>
                            <p class="text-sm text-gray-700 font-medium mb-2">Tipo de Seletor: <span class="font-mono text-xs bg-red-100 p-1 rounded">#{targeted_report[:failed_element][:selector_type] || 'Desconhecido'}</span></p>
                            <p class="text-sm text-gray-700 font-medium">Valor Buscado: <span class="font-mono text-xs bg-red-100 p-1 rounded break-all">#{targeted_report[:failed_element][:selector_value] || 'N/A'}</span></p>
                        </div>

                        <div class="bg-white p-4 rounded-lg shadow-xl">
                            <h2 class="text-xl font-bold text-gray-800 mb-4">Screenshot da Falha</h2>
                            <img src="data:image/png;base64,#{screenshot_base64}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
                        </div>
                    </div>

                    <div class="lg:col-span-2">
                        <div class="bg-white rounded-lg shadow-xl">
                            <div class="flex border-b border-gray-200">
                                <button class="tab-button active px-4 py-3 text-sm font-medium rounded-tl-lg" data-tab="similar">Sugestões de Reparo (#{targeted_report[:similar_elements].size})</button>
                                <button class="tab-button px-4 py-3 text-sm font-medium text-gray-600" data-tab="all">Dump Completo da Página (#{all_suggestions.size} Elementos)</button>
                            </div>

                            <div class="p-6">
                                <div id="similar" class="tab-content active">
                                    <h3 class="text-lg font-semibold text-indigo-700 mb-4">Elementos Semelhantes (Melhores Alternativas)</h3>
                                    #{"<p class='text-gray-500'>Nenhuma alternativa semelhante foi encontrada na página. O elemento pode ter sido removido ou o localizador está incorreto.</p>" if targeted_report[:similar_elements].empty?}
                                    <div class="space-y-4">
                                        #{targeted_report[:similar_elements].map { |el| "<div class='border border-indigo-100 p-3 rounded-lg bg-indigo-50'><p class='font-bold text-indigo-800 mb-2'>#{el[:name]}</p><ul>#{locators_html.call(el[:locators])}</ul></div>" }.join}
                                    </div>
                                </div>

                                <div id="all" class="tab-content">
                                    <h3 class="text-lg font-semibold text-indigo-700 mb-4">Dump Completo de Todos os Elementos da Tela</h3>
                                    <div class="max-h-[600px] overflow-y-auto space-y-2">
                                        #{all_elements_html.call(all_suggestions)}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <script>
                document.addEventListener('DOMContentLoaded', () => {
                    const tabs = document.querySelectorAll('.tab-button');
                    const contents = document.querySelectorAll('.tab-content');

                    tabs.forEach(tab => {
                        tab.addEventListener('click', () => {
                            const target = tab.getAttribute('data-tab');

                            tabs.forEach(t => t.classList.remove('active', 'text-white', 'text-gray-600', 'hover:bg-indigo-700'));
                            contents.forEach(c => c.classList.remove('active'));

                            tab.classList.add('active', 'text-white', 'bg-indigo-600');
                            document.getElementById(target).classList.add('active');
                        });
                    });
                     // Set initial active state for styling consistency
                    const activeTab = document.querySelector('.tab-button[data-tab="similar"]');
                    activeTab.classList.add('active', 'text-white', 'bg-indigo-600');
                });
            </script>
        </body>
        </html>
      HTML_REPORT
    end

    # --- Métodos de Suporte Existentes ---
    
    # ... (métodos setup_logger, extract_info_from_exception, find_similar_elements, etc.)

    def self.extract_info_from_exception(exception)
      message = exception.message
      info = {}
      
      patterns = [
        /(?:could not be found|cannot find element) using (.+)=['"](.+)['"]/i,
        /no such element: Unable to locate element: {"method":"([^"]+)","selector":"([^"]+)"}/i
      ]
      
      patterns.each do |pattern|
        match = message.match(pattern)
        if match
          selector_type = match[1].strip
          selector_value = match[2].strip
          
          info[:selector_type] = selector_type
          info[:selector_value] = selector_value.gsub(/['"]/, '')
          return info
        end
      end
      info
    end

    def self.find_similar_elements(doc, failed_info, platform)
      similar_elements = []
      doc.xpath('//*').each do |node|
        next if node.name == 'hierarchy'
        attrs = node.attributes.transform_values(&:value)
        
        is_similar = case platform
        when 'android'
          (attrs['resource-id']&.include?(failed_info[:selector_value]) ||
           attrs['text']&.include?(failed_info[:selector_value]) ||
           attrs['content-desc']&.include?(failed_info[:selector_value]))
        when 'ios'
          (attrs['accessibility-id']&.include?(failed_info[:selector_value]) ||
           attrs['label']&.include?(failed_info[:selector_value]) ||
           attrs['name']&.include?(failed_info[:selector_value]))
        else
          false
        end

        if is_similar
          name = self.suggest_name(node.name, attrs)
          locators = self.xpath_generator(node.name, attrs, platform)
          similar_elements << { name: name, locators: locators }
        end
      end
      similar_elements
    end
    
    def self.truncate(value)
      return value unless value.is_a?(String)
      value.size > MAX_VALUE_LENGTH ? "#{value[0...MAX_VALUE_LENGTH]}..." : value
    end

    def self.suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'
      name_base = nil
      
      ['content-desc', 'text', 'resource-id', 'label', 'name'].each do |attr_key|
        value = attrs[attr_key]
        if value.is_a?(String) && !value.empty?
          name_base = value
          break
        end
      end
      
      name_base ||= type
      
      truncated_name = truncate(name_base)
      sanitized_name = truncated_name.gsub(/[^a-zA-Z0-9\s]/, ' ').split.map(&:capitalize).join
      
      "#{pfx}#{sanitized_name}"
    end

    def self.xpath_generator(tag, attrs, platform)
      case platform
      when 'android'
        self.generate_android_xpaths(tag, attrs)
      when 'ios'
        self.generate_ios_xpaths(tag, attrs)
      else
        self.generate_unknown_xpaths(tag, attrs)
      end
    end

    def self.generate_android_xpaths(tag, attrs)
      locators = []
      
      if attrs['resource-id'] && !attrs['resource-id'].empty? && attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'resource_id_and_text', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\" and @text=\"#{self.truncate(attrs['text'])}\"]" }
      elsif attrs['resource-id'] && !attrs['resource-id'].empty? && attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'resource_id_and_content_desc', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\" and @content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end

      if attrs['resource-id'] && !attrs['resource-id'].empty?
        locators << { strategy: 'resource_id', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\"]" }
      end

      if attrs['resource-id'] && attrs['resource-id'].include?(':id/')
        id_part = attrs['resource-id'].split(':id/').last
        locators << { strategy: 'starts_with_resource_id', locator: "//#{tag}[starts-with(@resource-id, \"#{id_part}\")]" }
      end

      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'text', locator: "//#{tag}[@text=\"#{self.truncate(attrs['text'])}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'content_desc', locator: "//#{tag}[@content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end

      locators << { strategy: 'generic_tag', locator: "//#{tag}" }

      locators
    end

    def self.generate_ios_xpaths(tag, attrs)
      locators = []

      if attrs['accessibility-id'] && !attrs['accessibility-id'].empty? && attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'accessibility_id_and_label', locator: "//#{tag}[@accessibility-id=\"#{attrs['accessibility-id']}\" and @label=\"#{self.truncate(attrs['label'])}\"]" }
      end

      if attrs['accessibility-id'] && !attrs['accessibility-id'].empty?
        locators << { strategy: 'accessibility_id', locator: "//#{tag}[@accessibility-id=\"#{attrs['accessibility-id']}\"]" }
      end

      if attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'label', locator: "//#{tag}[@label=\"#{self.truncate(attrs['label'])}\"]" }
      end
      if attrs['name'] && !attrs['name'].empty?
        locators << { strategy: 'name', locator: "//#{tag}[@name=\"#{self.truncate(attrs['name'])}\"]" }
      end

      locators << { strategy: 'generic_tag', locator: "//#{tag}" }

      locators
    end

    def self.generate_unknown_xpaths(tag, attrs)
      locators = []
      if attrs['resource-id'] && !attrs['resource-id'].empty?
        locators << { strategy: 'resource_id', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'content_desc', locator: "//#{tag}[@content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end
      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'text', locator: "//#{tag}[@text=\"#{self.truncate(attrs['text'])}\"]" }
      end

      locators << { strategy: 'generic_tag', locator: "//#{tag}" }
      
      locators
    end

    def self.setup_logger
      @@logger = Logger.new(STDOUT)
      @@logger.level = Logger::INFO
      @@logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
      end
    end
  end
end
