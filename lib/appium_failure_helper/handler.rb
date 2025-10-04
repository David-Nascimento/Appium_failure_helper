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
          return
        end

        FileUtils.mkdir_p(@output_folder)

        triage_result = Analyzer.triage_error(@exception)
        platform_value = @driver.capabilities[:platform_name] || @driver.capabilities['platformName']
        platform = platform_value&.downcase || 'unknown'

        report_data = {
          exception: @exception, triage_result: triage_result,
          timestamp: @timestamp, platform: platform,
          screenshot_base_64: @driver.screenshot_as(:base64)
        }

        if triage_result == :locator_issue
          page_source = @driver.page_source
          doc = Nokogiri::XML(page_source)

          failed_info = Analyzer.extract_failure_details(@exception) || {}
          if failed_info.empty?
            failed_info = SourceCodeAnalyzer.extract_from_exception(@exception) || {}
          end

          if failed_info.empty?
            report_data[:triage_result] = :unidentified_locator_issue
          else
            page_analyzer = PageAnalyzer.new(page_source, platform)
            all_page_elements = page_analyzer.analyze || []

            best_candidate_analysis = Analyzer.perform_advanced_analysis(failed_info, all_page_elements, platform)

            alternative_xpaths = []
            if best_candidate_analysis
              if best_candidate_analysis[:attributes] && (target_path = best_candidate_analysis[:attributes][:path])
                target_node = doc.at_xpath(target_path)
                if target_node
                  alternative_xpaths = XPathFactory.generate_for_node(target_node)
                end
              end
            end

            report_data.merge!({
                                 page_source: page_source,
                                 failed_element: failed_info,
                                 best_candidate_analysis: best_candidate_analysis,
                                 alternative_xpaths: alternative_xpaths,
                                 all_page_elements: all_page_elements
                               })
          end
        end

        ReportGenerator.new(@output_folder, report_data).generate_all
        Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")
      rescue => e
        puts "--- ERRO FATAL NA GEM ---"
        puts "CLASSE: #{e.class}, MENSAGEM: #{e.message}"
        puts e.backtrace.join("\n")
        puts "-------------------------"
      end
      report_data
    end

    private

    def fetch_failed_element
      msg = @exception&.message.to_s

      if (m = msg.match(/using\s+["']?([^"']+)["']?\s+with\s+value\s+["']([^"']+)["']/i))
        return { selector_type: m[1], selector_value: m[2] }
      end

      if (m = msg.match(/"method"\s*:\s*"([^"]+)"[\s,}].*"selector"\s*:\s*"([^"]+)"/i))
        return { selector_type: m[1], selector_value: m[2] }
      end

      if (m = msg.match(/["']([^"']+)["']/))
        maybe_value = m[1]
        unified_map = ElementRepository.load_all rescue {}
        found = find_in_element_repository_by_value(maybe_value, unified_map)
        if found
          return found
        end

        guessed_type = msg[/\b(xpath|id|accessibility id|css)\b/i] ? $&.downcase : nil
        return { selector_type: guessed_type || 'unknown', selector_value: maybe_value }
      end

      begin
        code_info = SourceCodeAnalyzer.extract_from_exception(@exception) rescue {}
        unless code_info.nil? || code_info.empty?
          return code_info
        end
      rescue => _; end

      unified_map = ElementRepository.load_all rescue {}
      unified_map.each do |k, v|
        k_str = k.to_s.downcase
        if msg.downcase.include?(k_str)
          return normalize_repo_element(v)
        end
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
