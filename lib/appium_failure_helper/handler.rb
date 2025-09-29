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
      unless @driver && @driver.session_id
        Utils.logger.error("O Appium Failure Helper não pôde ser executado pois o driver é nulo ou a sessão já foi encerrada.")
        Utils.logger.error("Exceção original que causou a falha do cenário: #{@exception.message}")
        return
      end

      FileUtils.mkdir_p(@output_folder)
      page_source = @driver.page_source
      platform = @driver.capabilities['platformName']&.downcase || 'unknown'

      failed_info = Analyzer.extract_failure_details(@exception)
      failed_info ||= {}
      
      if failed_info.empty?
        Utils.logger.info("Análise da mensagem de erro falhou. Tentando analisar código-fonte...")
        failed_info = SourceCodeAnalyzer.extract_from_exception(@exception)
      end

      unified_element_map = ElementRepository.load_all
      de_para_result = Analyzer.find_de_para_match(failed_info, unified_element_map)
      
      page_analyzer = PageAnalyzer.new(page_source, platform)
      all_page_elements = page_analyzer.analyze || []

      similar_elements = Analyzer.find_similar_elements(failed_info, all_page_elements) || []

      code_search_results = CodeSearcher.find_similar_locators(failed_info) || []

      report_data = {
        failed_element: failed_info,
        similar_elements: similar_elements,
        de_para_analysis: de_para_result,
        code_search_results: code_search_results,
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