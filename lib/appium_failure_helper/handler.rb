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
      begin
        unless @driver && @driver.session_id
          Utils.logger.error("Helper não executado: driver nulo ou sessão encerrada.")
          return
        end

        FileUtils.mkdir_p(@output_folder)
        

        triage_result = Analyzer.triage_error(@exception)
        
        report_data = {
          exception: @exception,
          triage_result: triage_result,
          timestamp: @timestamp,
          platform: @driver.capabilities['platformName'] || @driver.capabilities[:platform_name] || 'unknown',
          screenshot_base64: @driver.screenshot_as(:base64)
        }

        if triage_result == :locator_issue
          page_source = @driver.page_source rescue nil
          doc = Nokogiri::XML(page_source)

          # Inicializa failed_info primeiro
          failed_info = Analyzer.extract_failure_details(@exception) || {}
          failed_info = SourceCodeAnalyzer.extract_from_exception(@exception) || {} if failed_info.empty?
          failed_info = { selector_type: 'unknown', selector_value: 'unknown' } if failed_info.empty?

          # Monta o report_data
          report_data[:page_source] = page_source
          report_data[:failed_element] = failed_info

          # Analisa elementos similares, alternative xpaths, de_para, code search etc
          unless failed_info.empty?
            page_analyzer = PageAnalyzer.new(page_source, report_data[:platform].to_s)
            all_page_elements = page_analyzer.analyze || []
            similar_elements = Analyzer.find_similar_elements(failed_info, all_page_elements) || []

            alternative_xpaths = []
            if !similar_elements.empty?
              target_suggestion = similar_elements.first
              if target_suggestion[:attributes] && (target_path = target_suggestion[:attributes][:path])
                target_node = doc.at_xpath(target_path)
                alternative_xpaths = XPathFactory.generate_for_node(target_node) if target_node
              end
            end

            unified_element_map = ElementRepository.load_all
            de_para_result = Analyzer.find_de_para_match(failed_info, unified_element_map)
            code_search_results = CodeSearcher.find_similar_locators(failed_info) || []

            report_data.merge!(
              similar_elements: similar_elements,
              alternative_xpaths: alternative_xpaths,
              de_para_analysis: de_para_result,
              code_search_results: code_search_results,
              all_page_elements: all_page_elements
            )
          end

          # Gera o relatório
          ReportGenerator.new(@output_folder, report_data).generate_all
          Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")

          report_data
          return
        end
      rescue => e
        Utils.logger.error("Erro fatal na GEM de diagnóstico: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end
  end
end