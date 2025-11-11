module AppiumFailureHelper
  class ReportGenerator
    def initialize(output_folder, report_data)
      @output_folder = output_folder
      @data = report_data.transform_keys(&:to_sym) rescue report_data

      # Inicializações seguras para evitar nil e erros de método 'presence'
      @dump = @data[:dump] || []
      @all_page_elements = @data[:all_page_elements].is_a?(Array) ? @data[:all_page_elements] : []
      @alternative_xpaths = if @data[:alternative_xpaths].is_a?(Array) && !@data[:alternative_xpaths].empty?
                              @data[:alternative_xpaths]
                            else
                              []
                            end
    end

    def generate_all
      generate_xml_report if @data[:page_source]
      generate_yaml_reports
      generate_html_report
    end

    private

    def safe_escape_html(value)
      CGI.escapeHTML(value.to_s)
    end

    def generate_xml_report
      FileUtils.mkdir_p(@output_folder) unless Dir.exist?(@output_folder)
      page_source = @data[:page_source]
      if page_source && !page_source.empty?
        File.write("#{ @output_folder }/page_source_#{ @data[:timestamp] }.xml", page_source)
      else
        puts "⚠️ Page source está vazio, XML não será gerado"
      end
    end

    def generate_yaml_reports
      analysis_report = {
        triage_result: @data[:triage_result],
        exception_class: @data[:exception]&.class.to_s,
        exception_message: @data[:exception]&.message,
        failed_element: @data[:failed_element],
        best_candidate_analysis: @data[:best_candidate_analysis],
        alternative_xpaths: @alternative_xpaths
      }

      File.write("#{@output_folder}/failure_analysis_#{@data[:timestamp]}.yaml", YAML.dump(analysis_report))
      File.write("#{@output_folder}/all_elements_dump_#{@data[:timestamp]}.yaml", YAML.dump(@all_page_elements)) if @all_page_elements.any?
    end

    def generate_html_report
      html_file_path = File.join(@output_folder, "report_#{@data[:timestamp]}.html")
      File.write(html_file_path, build_full_report)
      html_file_path
    end

    # === HTML ===
    def build_full_report
      failed_info = @data[:failed_element] || {}
      best_candidate = select_best_candidate(@data[:best_candidate_analysis])
      timestamp = @data[:timestamp]
      platform = @data[:platform]
      screenshot_base64 = @data[:screenshot_base_64]

      advanced_analysis_html = build_advanced_analysis(best_candidate)
      repair_strategies_content = build_repair_strategies(@alternative_xpaths)
      all_elements_html = build_all_elements_html(@all_page_elements)

      <<~HTML
      <!DOCTYPE html>
      <html lang="pt-BR">
      <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Relatório de Falha Appium - #{timestamp}</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style> .tab-button.active { border-bottom: 2px solid #4f46e5; color: #4f46e5; font-weight: 600; } .tab-content { display: none; } .tab-content.active { display: block; } </style>
      </head>
      <body class="bg-gray-100 p-4 sm:p-8">
        <div class="max-w-7xl mx-auto">
          <header class="mb-8 pb-4 border-b border-gray-300">
            <h1 class="text-3xl font-bold text-gray-800">Diagnóstico de Falha Automatizada</h1>
            <p class="text-sm text-gray-500">Relatório gerado em: #{timestamp} | Plataforma: #{platform.to_s.upcase}</p>
          </header>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <div class="lg:col-span-1 space-y-6">
              <div class="bg-white p-4 rounded-lg shadow-md border border-red-200">
                <h2 class="text-xl font-bold text-red-600 mb-4">Elemento com Falha</h2>
                <p class="text-sm text-gray-700 font-medium mb-2">Tipo de Seletor: <span class='font-mono text-xs bg-red-100 p-1 rounded'>#{safe_escape_html(failed_info[:selector_type])}</span></p>
                <p class="text-sm text-gray-700 font-medium">Valor Buscado: <span class='font-mono text-xs bg-red-100 p-1 rounded break-words'>#{safe_escape_html(failed_info[:selector_value])}</span></p>
              </div>
              <div class="bg-white p-4 rounded-lg shadow-md">
                <h2 class="text-xl font-bold text-gray-800 mb-4">Screenshot da Falha</h2>
                <img src="data:image/png;base64,#{screenshot_base64}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
              </div>
            </div>

            <div class="lg:col-span-2">
              <div class="bg-white rounded-lg shadow-md">
                <div class="flex border-b border-gray-200">
                  <button class="tab-button active px-4 py-3 text-sm" data-tab="analysis">Análise Avançada</button>
                  <button class="tab-button px-4 py-3 text-sm text-gray-600" data-tab="all">Dump Completo (#{@all_page_elements.size})</button>
                </div>

                <div class="p-6">
                  <div id="analysis" class="tab-content active">
                    <h3 class="text-lg font-semibold text-indigo-700 mb-4">Diagnóstico por Atributos Ponderados</h3>
                    #{advanced_analysis_html}
                    #{repair_strategies_content}
                  </div>

                  <div id="all" class="tab-content">
                    <h3 class="text-lg font-semibold text-gray-700 mb-4">Dump de Todos os Elementos da Tela</h3>
                    <div class="max-h-[800px] overflow-y-auto space-y-2">
                      #{all_elements_html}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <script>
            document.addEventListener('DOMContentLoaded', () => {
              const tabs = document.querySelectorAll('.tab-button');
              tabs.forEach(tab => {
                tab.addEventListener('click', (e) => {
                  e.preventDefault();
                  const target = tab.getAttribute('data-tab');
                  tabs.forEach(t => t.classList.remove('active'));
                  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                  tab.classList.add('active');
                  document.getElementById(target).classList.add('active');
                });
              });

              const carousel = document.getElementById('xpath-carousel');
              if (carousel) {
                const track = carousel.querySelector('.carousel-track');
                const items = carousel.querySelectorAll('.carousel-item');
                const prevButton = carousel.querySelector('.carousel-prev-footer');
                const nextButton = carousel.querySelector('.carousel-next-footer');
                const counter = carousel.querySelector('.carousel-counter');
                const totalItems = items.length;
                let currentIndex = 0;

                function updateCarousel() {
                  if(totalItems === 0) { if(counter) counter.textContent = "Nenhuma estratégia"; return; }
                  track.style.transform = `translateX(-${currentIndex * 100}%)`;
                  if(counter) counter.textContent = `Página ${currentIndex + 1} de ${totalItems}`;
                  if(prevButton) prevButton.disabled = currentIndex === 0;
                  if(nextButton) nextButton.disabled = currentIndex === totalItems - 1;
                }

                if(nextButton) nextButton.addEventListener('click', () => { if(currentIndex < totalItems - 1) currentIndex++; updateCarousel(); });
                if(prevButton) prevButton.addEventListener('click', () => { if(currentIndex > 0) currentIndex--; updateCarousel(); });
                if(totalItems > 0) updateCarousel();
              }
            });
          </script>
        </div>
      </body>
      </html>
      HTML
    end

    # === Helpers ===
    def select_best_candidate(candidates)
      return {} unless candidates.is_a?(Array) && candidates.any?
      candidates.max_by do |candidate|
        analysis = candidate[:analysis] || {}
        total_score = analysis.values.sum { |v| v[:similarity].to_f rescue 0.0 }
        total_score / [analysis.size, 1].max
      end
    end

    def build_advanced_analysis(best_candidate)
      return "<p class='text-gray-500'>Nenhum candidato provável encontrado.</p>" if best_candidate.nil? || best_candidate.empty?

      (best_candidate[:analysis] || {}).map do |key, data|
        data ||= {}
        match = data[:match]
        similarity = data[:similarity].to_f
        expected = data[:expected].to_s
        actual = data[:actual].to_s

        status_color, status_icon, status_text, bg_color = if match || similarity == 1.0
          ['text-green-700', '✅', "Correspondência Exata!", 'bg-green-50']
        elsif similarity > 0.7
          ['text-yellow-800', '⚠️', "Parecido (Encontrado: '#{CGI.escapeHTML(actual)}')", 'bg-yellow-50']
        else
          ['text-red-700', '❌', "Diferente! Esperado: '#{CGI.escapeHTML(expected)}'", 'bg-red-50']
        end

        <<~HTML
        <div class="p-4 rounded-lg mb-4 #{bg_color} border border-gray-200 shadow-sm">
          <div class="flex items-center mb-2">
            <span class="text-xl mr-2">#{status_icon}</span>
            <h4 class="font-semibold text-gray-900 text-sm">#{key.capitalize}</h4>
          </div>
          <p class="text-sm #{status_color} ml-6 break-words">
            #{status_text}<br>
            <span class="font-mono text-xs text-gray-700">Resource-id: #{CGI.escapeHTML(data[:actual].to_s)}</span>
          </p>
        </div>
        HTML
      end.join
    end


    def build_repair_strategies(strategies)
      return "<p class='text-gray-500'>Nenhuma estratégia de localização alternativa pôde ser gerada.</p>" if strategies.empty?

      # Ordena por confiabilidade: alta > media > baixa
      order = { alta: 3, media: 2, baixa: 1 }
      strategies = strategies.sort_by { |s| -order[s[:reliability]] }

      items_per_page = 4
      pages = strategies.each_slice(items_per_page).to_a

      pages_html = pages.map do |page|
        page_items = page.map do |s|
          reliability_color = case s[:reliability]
                              when :alta then 'bg-green-100 text-green-800'
                              when :media then 'bg-yellow-100 text-yellow-800'
                              else 'bg-red-100 text-red-800'
                              end
          <<~STR
          <li class='border-b border-gray-200 py-3 last:border-b-0'>
            <div class='flex justify-between items-center mb-1'>
              <p class='font-semibold text-indigo-800 text-sm'>#{safe_escape_html(s[:name])}</p>
              <span class='text-xs font-medium px-2 py-0.5 rounded-full #{reliability_color}'>#{safe_escape_html(s[:reliability].to_s.capitalize)}</span>
            </div>
            <div class='bg-gray-800 text-white p-2 rounded mt-1 text-xs whitespace-pre-wrap break-words font-mono'>
              <span class='font-bold text-indigo-400'>#{safe_escape_html(s[:strategy].to_s.upcase)}:</span>
              <code class='ml-1'>#{safe_escape_html(s[:locator])}</code>
            </div>
          </li>
          STR
        end.join
        "<div class='carousel-item w-full flex-shrink-0'><ul>#{page_items}</ul></div>"
      end.join

      <<~HTML
      <div id="xpath-carousel" class="relative">
        <div class="overflow-hidden">
          <div class="carousel-track flex transition-transform duration-300 ease-in-out">
            #{pages_html}
          </div>
        </div>
        <div class="flex items-center justify-center space-x-4 mt-4">
          <button class="carousel-prev-footer bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors">&lt; Anterior</button>
          <div class="carousel-counter text-center text-sm text-gray-600 font-medium"></div>
          <button class="carousel-next-footer bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors">Próximo &gt;</button>
        </div>
      </div>
      HTML
    end



    def build_all_elements_html(elements)
      return "<p class='text-gray-500'>Nenhum elemento capturado.</p>" if elements.empty?

      elements.map do |el|
        attrs = el[:attributes] || {}
        locators = el[:locators] || []
        critical = attrs[:critical] || false
        bg_color = critical ? 'bg-yellow-50 border-yellow-300' : 'bg-white border-gray-200'

        # Lista de atributos
        attributes_html = attrs.map do |k, v|
          "<li class='flex justify-between items-start p-1 text-xs font-mono'><span class='font-semibold text-gray-700'>#{CGI.escapeHTML(k.to_s)}</span>: <span class='text-gray-800 ml-2 break-words'>#{CGI.escapeHTML(v.to_s)}</span></li>"
        end.join

        # Lista de estratégias de XPath / locators
        locators_html = locators.map do |loc|
          "<li class='flex justify-between items-start p-1 text-xs font-mono bg-gray-50 rounded-md mb-1'><span class='font-semibold text-indigo-700'>#{CGI.escapeHTML(loc[:strategy].to_s.upcase)}</span>: <span class='text-gray-800 ml-2 break-words'>#{CGI.escapeHTML(loc[:locator].to_s)}</span></li>"
        end.join

        <<~HTML
        <details class="mb-2 border-l-4 #{bg_color} rounded-md p-2">
          <summary class="font-semibold text-sm text-gray-800 cursor-pointer">#{CGI.escapeHTML(el[:name].to_s)}</summary>
          <ul class="mt-1 space-y-1">
            #{attributes_html}
          </ul>
          <div class="mt-2">
            <p class="font-semibold text-gray-600 text-xs mb-1">Estratégias de Localização:</p>
            <ul class="space-y-1">
              #{locators_html}
            </ul>
          </div>
        </details>
        HTML
      end.join
    end
  end
end
