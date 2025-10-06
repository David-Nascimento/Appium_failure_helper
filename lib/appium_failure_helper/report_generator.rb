module AppiumFailureHelper
  class ReportGenerator
    def initialize(output_folder, report_data)
      @output_folder = output_folder
      @data = report_data
      @page_source = report_data[:page_source]
    end

    def generate_all
      generate_xml_report if @page_source
      generate_yaml_reports
      generate_html_report
    end

    private

    def generate_xml_report
      File.write("#{@output_folder}/page_source_#{@data[:timestamp]}.xml", @page_source)
    end

    def generate_yaml_reports
      analysis_report = {
        triage_result: @data[:triage_result],
        exception_class: @data[:exception].class.to_s,
        exception_message: @data[:exception].message,
        failed_element: @data[:failed_element],
        best_candidate_analysis: @data[:best_candidate_analysis],
        alternative_xpaths: @data[:alternative_xpaths] || []
      }
      File.open("#{@output_folder}/failure_analysis_#{@data[:timestamp]}.yaml", 'w') { |f| f.write(YAML.dump(analysis_report)) }

      if @data[:all_page_elements]
        File.open("#{@output_folder}/all_elements_dump_#{@data[:timestamp]}.yaml", 'w') { |f| f.write(YAML.dump(@data[:all_page_elements])) }
      end
    end

    def generate_html_report
      html_content = if @data[:triage_result] == :locator_issue && !(@data[:failed_element] || {}).empty?
                       build_full_report
                     else
                       build_simple_diagnosis_report(
                         title: "Diagnóstico Rápido de Falha",
                         message: "A análise profunda do seletor não foi executada ou falhou. Verifique a mensagem de erro original e o stack trace."
                       )
                     end
      File.write("#{@output_folder}/report_#{@data[:timestamp]}.html", html_content)
    end

    def build_full_report
      failed_info = @data[:failed_element] || {}
      all_suggestions = @data[:all_page_elements] || []
      best_candidate = @data[:best_candidate_analysis]
      alternative_xpaths = @data[:alternative_xpaths] || []
      timestamp = @data[:timestamp]
      platform = @data[:platform]
      screenshot_base64 = @data[:screenshot_base_64]

      locators_html = lambda do |locators|
        (locators || []).map { |loc| "<li class='flex justify-between items-center bg-gray-50 p-2 rounded-md mb-1 text-xs font-mono'><span class='font-bold text-indigo-600'>#{CGI.escapeHTML(loc[:strategy].to_s.upcase.gsub('_', ' '))}:</span><span class='text-gray-700 ml-2 overflow-auto max-w-[70%]'>#{CGI.escapeHTML(loc[:locator])}</span></li>" }.join
      end

      all_elements_html = lambda do |elements|
        (elements || []).map { |el| "<details class='border-b border-gray-200 py-3'><summary class='font-semibold text-sm text-gray-800 cursor-pointer'>#{CGI.escapeHTML(el[:name])}</summary><ul class='text-xs space-y-1 mt-2'>#{locators_html.call(el[:locators])}</ul></details>" }.join
      end

      failed_info_content = "<p class='text-sm text-gray-700 font-medium mb-2'>Tipo de Seletor: <span class='font-mono text-xs bg-red-100 p-1 rounded'>#{CGI.escapeHTML(failed_info[:selector_type].to_s)}</span></p><p class='text-sm text-gray-700 font-medium'>Valor Buscado: <span class='font-mono text-xs bg-red-100 p-1 rounded break-words'>#{CGI.escapeHTML(failed_info[:selector_value].to_s)}</span></p>"

      advanced_analysis_html = if best_candidate.nil?
                                 "<p class='text-gray-500'>Nenhum candidato provável foi encontrado na tela atual para uma análise detalhada.</p>"
                               else
                                 analysis_details = (best_candidate[:analysis] || {}).map do |key, data|
                                   status_color = 'bg-gray-400'
                                   status_icon = '⚪'
                                   status_text = "<b>#{key.capitalize}:</b><span class='ml-2 text-gray-700'>Não verificado</span>"

                                   if data[:match] == true || (data[:similarity] && data[:similarity] == 1.0)
                                     status_color = 'bg-green-500'
                                     status_icon = '✅'
                                     status_text = "<b>#{key.capitalize}:</b><span class='ml-2 text-gray-700'>Correspondência Exata!</span>"
                                   elsif data[:similarity] && data[:similarity] > 0.7
                                     status_color = 'bg-yellow-500'
                                     status_icon = '⚠️'
                                     status_text = "<b>#{key.capitalize}:</b><span class='ml-2 text-gray-700'>Parecido (Encontrado: '#{CGI.escapeHTML(data[:actual])}')</span>"
                                   else
                                     status_color = 'bg-red-500'
                                     status_icon = '❌'
                                     status_text = "<b>#{key.capitalize}:</b><span class='ml-2 text-gray-700'>Diferente! Esperado: '#{CGI.escapeHTML(data[:expected].to_s)}'</span>"
                                   end

                                   "<li class='flex items-center text-sm'><span class='w-4 h-4 rounded-full #{status_color} mr-3 flex-shrink-0 flex items-center justify-center text-white text-xs'>#{status_icon}</span><div class='truncate'>#{status_text}</div></li>"
                                 end.join

                                 suggestion_text = "O `resource-id` pode ter mudado ou o `text` está diferente. Considere usar um seletor mais robusto baseado nos atributos que corresponderam."
                                 if (best_candidate[:analysis][:id] || {})[:match] == true && (best_candidate[:analysis][:text] || {})[:similarity].to_f < 0.7
                                   suggestion_text = "O `resource-id` corresponde, mas o texto é diferente. **Recomendamos fortemente usar o `resource-id` para este seletor.**"
                                 end

                                 <<~HTML
                                  <div class='border border-sky-200 bg-sky-50 p-4 rounded-lg'>
                                    <h4 class='font-bold text-sky-800 mb-3'>Candidato Mais Provável Encontrado: <span class='font-mono bg-sky-100 text-sky-900 rounded px-2 py-1 text-sm'>#{CGI.escapeHTML(best_candidate[:name])}</span></h4>
                                    <ul class='space-y-2 mb-4'>#{analysis_details}</ul>
                                    <div class='bg-sky-100 border-l-4 border-sky-500 text-sky-900 text-sm p-3 rounded-r-lg'>
                                      <p><b>Sugestão:</b> #{suggestion_text}</p>
                                    </div>
                                  </div>
                                HTML
                               end

      repair_strategies_content =  if alternative_xpaths.empty?
                                     "<p class='text-gray-500'>Nenhuma estratégia de localização alternativa pôde ser gerada.</p>"
                                   else
                                     pages = alternative_xpaths.each_slice(6).to_a
                                     carousel_items = pages.map do |page_strategies|
                                       strategy_list_html = page_strategies.map do |strategy|
                                         reliability_color = case strategy[:reliability]
                                                             when :alta then 'bg-green-100 text-green-800'
                                                             when :media then 'bg-yellow-100 text-yellow-800'
                                                             else 'bg-red-100 text-red-800'
                                                             end
                                         # CORREÇÃO: Adiciona o tipo de estratégia (ID, XPATH) ao lado do seletor
                                         <<~STRATEGY_ITEM
              <li class='border-b border-gray-200 py-3 last:border-b-0'>
                <div class='flex justify-between items-center mb-1'>
                  <p class='font-semibold text-indigo-800 text-sm'>#{CGI.escapeHTML(strategy[:name])}</p>
                  <span class='text-xs font-medium px-2 py-0.5 rounded-full #{reliability_color}'>#{CGI.escapeHTML(strategy[:reliability].to_s.capitalize)}</span>
                </div>
                <div class='bg-gray-800 text-white p-2 rounded mt-1 text-xs whitespace-pre-wrap break-words font-mono'>
                  <span class='font-bold text-indigo-400'>#{CGI.escapeHTML(strategy[:strategy].to_s.upcase)}:</span>
                  <code class='ml-1'>#{CGI.escapeHTML(strategy[:locator])}</code>
                </div>
              </li>
            STRATEGY_ITEM
                                       end.join
                                       "<div class='carousel-item w-full flex-shrink-0'><ul>#{strategy_list_html}</ul></div>"
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
      <<~HTML_REPORT
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
                <div class="bg-white p-4 rounded-lg shadow-md">
                  <h2 class="text-xl font-bold text-gray-800 mb-4">Screenshot da Falha</h2>
                  <img src="data:image/png;base64,#{screenshot_base64}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
                </div>
              </div>
              <div class="lg:col-span-2">
                <div class="bg-white rounded-lg shadow-md">
                  <div class="flex border-b border-gray-200">
                    <button class="tab-button active px-4 py-3 text-sm" data-tab="analysis">Análise Avançada</button>
                    <button class="tab-button px-4 py-3 text-sm text-gray-600" data-tab="all">Dump Completo (#{all_suggestions.size})</button>
                  </div>
                  <div class="p-6">
                    <div id="analysis" class="tab-content active">
                      <h3 class="text-lg font-semibold text-indigo-700 mb-4">Diagnóstico por Atributos Ponderados</h3>
                      #{advanced_analysis_html}
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
            });
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
    end

    def build_simple_diagnosis_report(title:, message:)
      exception = @data[:exception]
      screenshot = @data[:screenshot_base_64]
      error_message_html = CGI.escapeHTML(exception.message.to_s)
      backtrace_html = CGI.escapeHTML(exception.backtrace.join("\n"))

      <<~HTML_REPORT
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
          <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Diagnóstico de Falha - #{title}</title>
          <script src="https://cdn.tailwindcss.com"></script>
        </head>
        <body class="bg-gray-100 p-4 sm:p-8">
          <div class="max-w-4xl mx-auto">
            <header class="mb-8 pb-4 border-b border-gray-200">
              <h1 class="text-3xl font-bold text-gray-800">Diagnóstico de Falha Automatizada</h1>
              <p class="text-sm text-gray-500">Relatório gerado em: #{@data[:timestamp]} | Plataforma: #{@data[:platform].to_s.upcase}</p>
            </header>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div class="md:col-span-1">
                <div class="bg-white p-4 rounded-lg shadow-md">
                  <h2 class="text-xl font-bold text-gray-800 mb-4">Screenshot da Falha</h2>
                  <img src="data:image/png;base64,#{screenshot}" alt="Screenshot da Falha" class="w-full rounded-md shadow-lg border border-gray-200">
                </div>
              </div>
              <div class="md:col-span-2 space-y-6">
                <div class="bg-white p-6 rounded-lg shadow-md">
                  <h2 class="text-xl font-bold text-red-600 mb-4">Diagnóstico: #{title}</h2>
                  <div class="bg-red-50 border-l-4 border-red-500 text-red-800 p-4 rounded-r-lg">
                    <p class="font-semibold">Causa Provável:</p>
                    <p>#{message}</p>
                  </div>
                </div>
                <div class="bg-white p-6 rounded-lg shadow-md">
                  <h3 class="text-lg font-semibold text-gray-700 mb-2">Mensagem de Erro Original</h3>
                  <pre class="bg-gray-800 text-white p-4 rounded text-xs whitespace-pre-wrap break-words max-h-48 overflow-y-auto"><code>#{error_message_html}</code></pre>
                </div>
                <div class="bg-white p-6 rounded-lg shadow-md">
                  <h3 class="text-lg font-semibold text-gray-700 mb-2">Stack Trace</h3>
                  <pre class="bg-gray-800 text-white p-4 rounded text-xs whitespace-pre-wrap break-words max-h-72 overflow-y-auto"><code>#{backtrace_html}</code></pre>
                </div>
              </div>
            </div>
          </div>
        </body>
        </html>
      HTML_REPORT
    end
  end
end