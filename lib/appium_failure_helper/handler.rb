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
      report_data = {}
      begin
        unless @driver && @driver.session_id
          Utils.logger.error("Helper não executado: driver nulo ou sessão encerrada.")
          return {}
        end

        FileUtils.mkdir_p(@output_folder)

        triage_result = Analyzer.triage_error(@exception)
        screenshot_b64 = begin
          @driver.screenshot_as(:base64)
        rescue
          nil
        end
        report_data = {
          exception: @exception,
          triage_result: triage_result,
          timestamp: @timestamp,
          platform: (@driver.capabilities['platformName'] rescue @driver.capabilities[:platform_name]) || 'unknown',
          screenshot_base64: screenshot_b64
        }

        if triage_result == :locator_issue
          page_source = @driver.page_source rescue nil
          doc = Nokogiri::XML(page_source) rescue nil

          failed_info = fetch_failed_element

          report_data[:page_source] = page_source
          report_data[:failed_element] = failed_info

          unless failed_info.nil? || failed_info.empty?
            page_analyzer = PageAnalyzer.new(page_source, report_data[:platform].to_s) rescue nil
            all_page_elements = page_analyzer ? (page_analyzer.analyze || []) : []
            similar_elements = Analyzer.find_similar_elements(failed_info, all_page_elements) || []
            alternative_xpaths = generate_alternative_xpaths(similar_elements, doc)
            unified_element_map = ElementRepository.load_all rescue {}
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

          ReportGenerator.new(@output_folder, report_data).generate_all
          Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")
        end

      rescue => e
        Utils.logger.error("Erro fatal na GEM de diagnóstico: #{e.message}\n#{e.backtrace.join("\n")}")
        report_data = { exception: @exception, triage_result: :error } if report_data.nil? || report_data.empty?
      ensure
        return report_data
      end
    end

    private

    def fetch_failed_element
      msg = @exception&.message.to_s

      # 1) pattern: using "type" with value "value"
      if (m = msg.match(/using\s+["']?([^"']+)["']?\s+with\s+value\s+["']([^"']+)["']/i))
        return { selector_type: m[1], selector_value: m[2] }
      end

      # 2) JSON-like: {"method":"id","selector":"btn"}
      if (m = msg.match(/"method"\s*:\s*"([^"]+)"[\s,}].*"selector"\s*:\s*"([^"]+)"/i))
        return { selector_type: m[1], selector_value: m[2] }
      end

      # 3) generic quoted token "value" or 'value'
      if (m = msg.match(/["']([^"']+)["']/))
        maybe_value = m[1]
        # try lookup in repo by that value
        unified_map = ElementRepository.load_all rescue {}
        found = find_in_element_repository_by_value(maybe_value, unified_map)
        if found
          return found
        end

        # guess type from message heuristics
        guessed_type = msg[/\b(xpath|id|accessibility id|css)\b/i] ? $&.downcase : nil
        return { selector_type: guessed_type || 'unknown', selector_value: maybe_value }
      end

      # 4) try SourceCodeAnalyzer
      begin
        code_info = SourceCodeAnalyzer.extract_from_exception(@exception) rescue {}
        unless code_info.nil? || code_info.empty?
          return code_info
        end
      rescue => _; end

      # 5) fallback: try to inspect unified map for likely candidates (keys or inner values)
      unified_map = ElementRepository.load_all rescue {}
      # try to match any key that looks like an identifier present in the message
      unified_map.each do |k, v|
        k_str = k.to_s.downcase
        if msg.downcase.include?(k_str)
          return normalize_repo_element(v)
        end
        # inspect value fields
        vals = []
        if v.is_a?(Hash)
          vals << v['valor'] if v.key?('valor')
          vals << v['value'] if v.key?('value')
          vals << v[:valor] if v.key?(:valor)
          vals << v[:value] if v.key?(:value)
        end
        vals.compact!
        vals.each do |vv|
          if vv.to_s.downcase == vv.to_s.downcase && msg.downcase.include?(vv.to_s.downcase)
            return normalize_repo_element(v)
          end
        end
      end

      # final fallback
      debug_log("fetch_failed_element: fallback unknown")
      { selector_type: 'unknown', selector_value: 'unknown' }
    end

    def find_in_element_repository_by_value(value, map = {})
      return nil if value.nil? || value.to_s.strip.empty?
      normalized_value = value.to_s.downcase.strip
      map.each do |k, v|
        entry = v.is_a?(Hash) ? v : (v.respond_to?(:to_h) ? v.to_h : nil)
        next unless entry
        entry_val = entry['valor'] || entry['value'] || entry[:valor] || entry[:value] || entry['locator'] || entry[:locator]
        next unless entry_val
        return normalize_repo_element(entry) if entry_val.to_s.downcase.strip == normalized_value
      end
      nil
    end

    def normalize_repo_element(entry)
      return nil unless entry.is_a?(Hash)
      tipo = entry['tipoBusca'] || entry[:tipoBusca] || entry['type'] || entry[:type] || entry['search_type'] || entry[:search]
      valor = entry['valor'] || entry[:value] || entry[:locator] || entry[:valor_final] || entry[:value_final]
      return nil unless valor
      { selector_type: (tipo || 'unknown'), selector_value: valor.to_s }
    end

    def generate_alternative_xpaths(similar_elements, doc)
      alternative_xpaths = []
      if !similar_elements.empty?
        target_suggestion = similar_elements.first
        if target_suggestion[:attributes] && (target_path = target_suggestion[:attributes][:path])
          target_node = doc.at_xpath(target_path) rescue nil
          alternative_xpaths = XPathFactory.generate_for_node(target_node) if target_node
        end
      end
      alternative_xpaths
    end
  end
end
