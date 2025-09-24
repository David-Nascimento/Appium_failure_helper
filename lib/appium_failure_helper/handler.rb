module AppiumFailureHelper
  class Handler
    def self.call(driver, exception)
      new(driver, exception).call
    end

    def initialize(driver, exception)
      @driver = driver
      @exception = exception
      @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      @output_folder = "reports_failure/failure_#{@timestamp}"
    end

    def call
      FileUtils.mkdir_p(@output_folder)
      page_source = @driver.page_source
      platform = @driver.capabilities['platformName']&.downcase || 'unknown'

      failed_info = Analyzer.extract_failure_details(@exception)
      
      # ALTERADO: Agora busca em todas as fontes de dados
      logical_name_key = failed_info[:selector_value].to_s.gsub(/^#/, '')
      
      # 1. Busca nos arquivos YAML dinâmicos
      element_map_yaml = ElementRepository.load_all_from_yaml
      de_para_yaml_result = Analyzer.find_de_para_match(failed_info, element_map_yaml)

      # 2. Busca no arquivo Ruby
      de_para_rb_result = ElementRepository.find_in_ruby_file(logical_name_key)

      # 3. Analisa a tela atual
      page_analyzer = PageAnalyzer.new(page_source, platform)
      all_page_elements = page_analyzer.analyze
      similar_elements = Analyzer.find_similar_elements(failed_info, all_page_elements)

      # Organiza TODOS os resultados para o relatório
      report_data = {
        failed_element: failed_info,
        similar_elements: similar_elements,
        de_para_yaml_analysis: de_para_yaml_result, # Resultado da análise YAML
        de_para_rb_analysis: de_para_rb_result,   # Resultado da análise Ruby
        all_page_elements: all_page_elements,
        screenshot_base64: @driver.screenshot_as(:base64),
        platform: platform,
        timestamp: @timestamp
      }

      ReportGenerator.new(@output_folder, page_source, report_data).generate_all
      
      Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")
    rescue => e
      Utils.logger.error("Erro ao capturar detalhes da falha: #{e.message}\n#{e.backtrace.join("\n")}")
    end
  end
end