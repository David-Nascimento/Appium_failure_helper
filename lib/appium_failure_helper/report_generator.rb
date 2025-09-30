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
        de_para_analysis: @data[:de_para_analysis],
        code_search_results: @data[:code_search_results],
        alternative_xpaths: @data[:alternative_xpaths]
      }
      File.open("#{@output_folder}/failure_analysis_#{@data[:timestamp]}.yaml", 'w') { |f| f.write(YAML.dump(analysis_report)) }
      File.open("#{@output_folder}/all_elements_dump_#{@data[:timestamp]}.yaml", 'w') { |f| f.write(YAML.dump(@data[:all_page_elements])) }
    end

    def generate_html_report
      failed_info = @data[:failed_element] || {}
      similar_elements = @data[:similar_elements] || []
      all_suggestions = @data[:all_page_elements] || []
      de_para_analysis = @data[:de_para_analysis]
      code_search_results = @data[:code_search_results] || []
      alternative_xpaths = @data[:alternative_xpaths] || []
      timestamp = @data[:timestamp]
      platform = @data[:platform]
      screenshot_base64 = @data[:screenshot_base64]
      
      locators_html = lambda do |locators|
        (locators || []).map do |loc|
          strategy_text = loc[:strategy].to_s.upcase.gsub('_', ' ')
          "<li class='flex justify-between items-center bg-gray-50 p-2 rounded-md mb-1 text-xs font-mono'><span class='font-bold text-indigo-600'>#{CGI.escapeHTML(strategy_text)}:</span><span class='text-gray-700 ml-2 overflow-auto max-w-[70%]'>#{CGI.escapeHTML(loc[:locator])}</span></li>"
        end.join
      end

      all_elements_html = lambda do |elements|
        (elements || []).map { |el| "<details class='border-b border-gray-200 py-3'><summary class='font-semibold text-sm text-gray-800 cursor-pointer'>#{CGI.escapeHTML(el[:name])}</summary><ul class='text-xs space-y-1 mt-2'>#{locators_html.call(el[:locators])}</ul></details>" }.join
      end
      
      de_para_html = ""
      failed_info_content = ""

      code_search_html = ""
      unless code_search_results.empty?
        suggestions_list = code_search_results.map do |match|
          score_percent = (match[:score] * 100).round(1)
          <<~SUGGESTION
            <div class='border border-sky-200 bg-sky-50 p-3 rounded-lg mb-2'>
              <p class='text-sm text-gray-600'>Encontrado em: <strong class='font-mono'>#{match[:file]}:#{match[:line_number]}</strong></p>
              <pre class='bg-gray-800 text-white p-2 rounded mt-2 text-xs overflow-auto'><code>#{CGI.escapeHTML(match[:code])}</code></pre>
              <p class='text-xs text-green-600 mt-1'>Similaridade: #{score_percent}%</p>
            </div>
          SUGGESTION
        end.join
        code_search_html = <<~HTML
          <div class="bg-white p-4 rounded-lg shadow-md">
            <h2 class="text-xl font-bold text-sky-700 mb-4">Sugestões Encontradas no Código</h2>
            #{suggestions_list}
          </div>
        HTML
      end

      failed_info_content = if failed_info && !failed_info.empty?
         "<p class='text-sm text-gray-700 font-medium mb-2'>Tipo de Seletor: <span class='font-mono text-xs bg-red-100 p-1 rounded'>#{CGI.escapeHTML(failed_info[:selector_type].to_s)}</span></p><p class='text-sm text-gray-700 font-medium'>Valor Buscado: <span class='font-mono text-xs bg-red-100 p-1 rounded break-all'>#{CGI.escapeHTML(failed_info[:selector_value].to_s)}</span></p>"
      else
        "<p class='text-sm text-gray-500'>O localizador exato não pôde ser extraído.</p>"
      end

      repair_strategies_content = if alternative_xpaths.empty?
        "<p class='text-gray-500'>Nenhuma estratégia de XPath alternativa pôde ser gerada para o elemento alvo.</p>"
      else
        pages = alternative_xpaths.each_slice(6).to_a
        
        carousel_items = pages.map do |page_strategies|
          strategy_list_html = page_strategies.map do |strategy|
            reliability_color = case strategy[:reliability]
                                when :alta then 'bg-green-100 text-green-800'
                                when :media then 'bg-yellow-100 text-yellow-800'
                                else 'bg-red-100 text-red-800'
                                end
            <<~STRATEGY_ITEM
              <div class='border border-gray-200 rounded-lg p-3 bg-white'>
                <div class='flex justify-between items-center mb-2'>
                  <p class='font-semibold text-indigo-800 text-sm'>#{CGI.escapeHTML(strategy[:name])}</p>
                  <span class='text-xs font-medium px-2 py-0.5 rounded-full #{reliability_color}'>#{CGI.escapeHTML(strategy[:reliability].to_s.capitalize)}</span>
                </div>
                <pre class='bg-gray-800 text-white p-2 rounded text-xs whitespace-pre-wrap break-words'><code>#{CGI.escapeHTML(strategy[:locator])}</code></pre>
              </div>
            STRATEGY_ITEM
          end.join
          "<div class='carousel-item w-full flex-shrink-0'><div class='space-y-3'>#{strategy_list_html}</div></div>"
        end.join

        <<~CAROUSEL
          <div id="xpath-carousel" class="relative">
            <div class="overflow-hidden">
              <div class="carousel-track flex transition-transform duration-300 ease-in-out">
                #{carousel_items}
              </div>
            </div>
            <div class="flex items-center justify-center space-x-4 mt-4">
              <button class="carousel-prev-footer bg-gray-200 hover:bg-gray-300 text-gray-800 font-bold py-2 px-4 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                &lt; Anterior
              </button>
              <div class="carousel-counter text-center text-sm text-gray-600 font-medium"></div>
              <button class="carousel-next-footer bg-gray-200 hover:bg-gray-300 text-gray-800 font-bold py-2 px-4 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                Próximo &gt;
              </button>
            </div>
          </div>
        CAROUSEL
      end

      similar_elements_content = if similar_elements.empty?
        "<p class='text-gray-500'>Nenhuma alternativa semelhante foi encontrada na tela atual.</p>"
      else
        carousel_items = similar_elements.map do |el|
          score_percent = (el[:score] * 100).round(1)
          <<~ITEM
            <div class="carousel-item w-full flex-shrink-0">
              <div class='border border-indigo-100 p-4 rounded-lg bg-indigo-50'>
                <p class='font-bold text-indigo-800 mb-2'>#{CGI.escapeHTML(el[:name])} <span class='text-xs font-normal text-green-600 bg-green-100 rounded-full px-2 py-1 ml-2'>Similaridade: #{score_percent}%</span></p>
                <ul>#{locators_html.call(el[:locators])}</ul>
              </div>
            </div>
          ITEM
        end.join
        <<~CAROUSEL
          <div id="similar-elements-carousel" class="relative">
            <div class="overflow-hidden rounded-lg bg-white"><div class="carousel-track flex transition-transform duration-300 ease-in-out">#{carousel_items}</div></div>
            <div class="flex items-center justify-center space-x-4 mt-4">
              <button class="carousel-prev-footer bg-gray-200 hover:bg-gray-300 text-gray-800 font-bold py-2 px-4 rounded-lg disabled:opacity-50"> &lt; Anterior </button>
              <div class="carousel-counter text-center text-sm text-gray-600 font-medium"></div>
              <button class="carousel-next-footer bg-gray-200 hover:bg-gray-300 text-gray-800 font-bold py-2 px-4 rounded-lg disabled:opacity-50"> Próximo &gt; </button>
            </div>
          </div>
        CAROUSEL
      end

      html_content = <<~HTML_REPORT
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
                  #{failed_info_content}
                </div>
                #{code_search_html}
                <div class="bg-white p-4 rounded-lg shadow-md">
                  <h2 class="text-xl font-bold text-gray-800 mb-4">Screenshot da Falha</h2>
                  <img src="data:image/png;base64,#{screenshot_base64}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
                </div>
              </div>
              <div class="lg:col-span-2">
                <div class="bg-white rounded-lg shadow-md">
                  <div class="flex border-b border-gray-200">
                    <button class="tab-button active px-4 py-3 text-sm" data-tab="strategies">Estratégias de Reparo (#{alternative_xpaths.size})</button>
                    <button class="tab-button px-4 py-3 text-sm text-gray-600" data-tab="all">Dump Completo (#{all_suggestions.size})</button>
                  </div>
                  <div class="p-6">
                    <div id="strategies" class="tab-content active">
                      <h3 class="text-lg font-semibold text-indigo-700 mb-4">Estratégias de Localização Alternativas</h3>
                      #{repair_strategies_content}
                    </div>
                    <div id="all" class="tab-content">
                      <h3 class="text-lg font-semibold text-gray-700 mb-4">Dump de Todos os Elementos da Tela</h3>
                      <div class="max-h-[800px] overflow-y-auto space-y-2">#{all_elements_html.call(all_suggestions)}</div>
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
                  if (totalItems === 0) {
                    if(counter) counter.textContent = "";
                    return;
                  };
                  track.style.transform = `translateX(-${currentIndex * 100}%)`;
                  if (counter) { counter.textContent = `Página ${currentIndex + 1} de ${totalItems}`; }
                  if (prevButton) { prevButton.disabled = currentIndex === 0; }
                  if (nextButton) { nextButton.disabled = currentIndex === totalItems - 1; }
                }

                if (nextButton) {
                  nextButton.addEventListener('click', () => {
                    if (currentIndex < totalItems - 1) { currentIndex++; updateCarousel(); }
                  });
                }

                if (prevButton) {
                  prevButton.addEventListener('click', () => {
                    if (currentIndex > 0) { currentIndex--; updateCarousel(); }
                  });
                }
                
                if (totalItems > 0) { updateCarousel(); }
              }
            });
          </script>
        </body>
        </html>
      HTML_REPORT

      File.write("#{@output_folder}/report_#{@data[:timestamp]}.html", html_content)
    end
  end
end