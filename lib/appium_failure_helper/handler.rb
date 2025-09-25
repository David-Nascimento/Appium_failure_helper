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
      unified_element_map = ElementRepository.load_all
      de_para_result = Analyzer.find_de_para_match(failed_info, unified_element_map)

      page_analyzer = PageAnalyzer.new(page_source, platform)
      all_page_elements = page_analyzer.analyze
      similar_elements = Analyzer.find_similar_elements(failed_info, all_page_elements)

      report_data = {
        failed_element: failed_info,
        similar_elements: similar_elements,
        de_para_analysis: de_para_result,
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