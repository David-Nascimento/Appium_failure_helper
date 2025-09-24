module AppiumFailureHelper
  class ReportGenerator
    def initialize(output_folder, page_source, report_data)
      @output_folder = output_folder
      @page_source = page_source
      @data = report_data
    end

    def generate_all
      generate_xml_report
      generate_yaml_reports
      generate_html_report
    end

    private

    def generate_xml_report
      File.write("#{@output_folder}/page_source_#{@data[:timestamp]}.xml", @page_source)
    end

    def generate_yaml_reports
      analysis_report = {
        failed_element: @data[:failed_element],
        similar_elements: @data[:similar_elements],
        de_para_yaml_analysis: @data[:de_para_yaml_analysis],
        de_para_rb_analysis: @data[:de_para_rb_analysis]
      }
      File.open("#{@output_folder}/failure_analysis_#{@data[:timestamp]}.yaml", 'w') { |f| f.write(YAML.dump(analysis_report)) }
      File.open("#{@output_folder}/all_elements_dump_#{@data[:timestamp]}.yaml", 'w') { |f| f.write(YAML.dump(@data[:all_page_elements])) }
    end

    def generate_html_report
      # ... (Lambdas locators_html e all_elements_html permanecem iguais) ...
      locators_html = ->(locators) { locators.map { |loc| "..." }.join }
      all_elements_html = ->(elements) { elements.map { |el| "..." }.join }

      # Prepara o conteúdo dinâmico
      failed_info = @data[:failed_element]
      similar_elements = @data[:similar_elements]
      de_para_yaml = @data[:de_para_yaml_analysis]
      de_para_rb = @data[:de_para_rb_analysis]
      all_suggestions = @data[:all_page_elements]
      
      # NOVO: Gera dois blocos de HTML, um para cada análise
      
      # Bloco de análise YAML
      de_para_yaml_html = ""
      if de_para_yaml
        de_para_yaml_html = <<~HTML
          <div class="bg-green-50 border border-green-200 p-4 rounded-lg shadow-md mb-6">
            <h3 class="text-lg font-bold text-green-800 mb-2">Análise de Mapeamento YAML (.yaml)</h3>
            <p class="text-sm text-gray-700 mb-1">O nome lógico <strong class="font-mono bg-gray-200 px-1 rounded">#{CGI.escapeHTML(de_para_yaml[:logical_name])}</strong> foi encontrado nos arquivos .yaml do projeto!</p>
            <p class="text-sm text-gray-700">O localizador correto definido é:</p>
            <div class="font-mono text-xs bg-green-100 p-2 mt-2 rounded">
              <span class="font-bold">#{CGI.escapeHTML(de_para_yaml[:correct_locator]['tipoBusca'].upcase)}:</span>
              <span class="break-all">#{CGI.escapeHTML(de_para_yaml[:correct_locator]['valor'])}</span>
            </div>
          </div>
        HTML
      end
      
      # Bloco de análise Ruby
      de_para_rb_html = ""
      if de_para_rb
        if de_para_rb[:found]
          de_para_rb_html = <<~HTML
            <div class="bg-green-50 border border-green-200 p-4 rounded-lg shadow-md mb-6">
              <h3 class="text-lg font-bold text-green-800 mb-2">Análise de Mapeamento Ruby (.rb)</h3>
              <p class="text-sm text-gray-700">A definição do elemento foi encontrada com sucesso no arquivo <strong class="font-mono bg-gray-200 px-1 rounded">#{de_para_rb[:path]}</strong>.</p>
            </div>
          HTML
        else
          de_para_rb_html = <<~HTML
            <div class="bg-yellow-50 border border-yellow-200 p-4 rounded-lg shadow-md mb-6">
              <h3 class="text-lg font-bold text-yellow-800 mb-2">Análise de Mapeamento Ruby (.rb)</h3>
              <p class="text-sm text-gray-700">O elemento <strong class="font-mono bg-gray-200 px-1 rounded">#{CGI.escapeHTML(failed_info[:selector_value].to_s)}</strong> NÃO foi encontrado no arquivo <strong class="font-mono bg-gray-200 px-1 rounded">#{de_para_rb[:path]}</strong>.</p>
              <p class="text-xs text-gray-500 mt-1">Motivo: #{de_para_rb[:reason]}</p>
            </div>
          HTML
        end
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

      html_content = <<~HTML_REPORT
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Relatório de Falha Appium - #{@data[:timestamp]}</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <style> body { font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto; } .tab-content { display: none; } .tab-content.active { display: block; } .tab-button.active { background-color: #4f46e5; color: white; } </style>
        </head>
        <body class="bg-gray-50 p-8">
          <div class="max-w-7xl mx-auto">
            <header class="mb-8 pb-4 border-b border-gray-300">
              <h1 class="text-3xl font-bold text-gray-800">Diagnóstico de Falha Automatizada</h1>
              <p class="text-sm text-gray-500">Relatório gerado em: #{@data[:timestamp]} | Plataforma: #{@data[:platform].upcase}</p>
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
                  <img src="data:image/png;base64,#{@data[:screenshot_base64]}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
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

      File.write("#{@output_folder}/report_#{@data[:timestamp]}.html", html_content)
    end
  end
end