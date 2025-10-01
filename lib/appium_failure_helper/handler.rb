# lib/appium_failure_helper/handler.rb
module AppiumFailureHelper
  class Handler
    def self.call(driver, exception)
      new(driver, exception).call
    end

    def initialize(driver, exception)
      @driver = driver; @exception = exception; @timestamp = Time.now.strftime('%Y%m%d_%H%M%S'); @output_folder = "reports_failure/failure_#{@timestamp}"
    end

    def call
      begin
        unless @driver && @driver.session_id
          Utils.logger.error("Helper não executado: driver nulo ou sessão encerrada.")
          return
        end

        FileUtils.mkdir_p(@output_folder)
        triage_result = Analyzer.triage_error(@exception)
        
        report_data = { exception: @exception, triage_result: triage_result, timestamp: @timestamp, platform: @driver.capabilities[:platformName], screenshot_base64: @driver.screenshot_as(:base64) }

        if triage_result == :locator_issue
          page_source = @driver.page_source
          failed_info = Analyzer.extract_failure_details(@exception)

          # Se a extração da mensagem falhou, geramos o relatório simples
          if failed_info.empty?
             report_data[:triage_result] = :unidentified_locator_issue
          else
            page_analyzer = PageAnalyzer.new(page_source, report_data[:platform].to_s)
            all_page_elements = page_analyzer.analyze
            best_candidate_analysis = Analyzer.perform_advanced_analysis(failed_info, all_page_elements)

            report_data.merge!({
              page_source: page_source,
              failed_element: failed_info,
              best_candidate_analysis: best_candidate_analysis,
              all_page_elements: all_page_elements
            })
          end
        end

        ReportGenerator.new(@output_folder, report_data).generate_all
        Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")
      rescue => e
        Utils.logger.error("Erro fatal na GEM: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end
  end
end