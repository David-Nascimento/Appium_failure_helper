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
        unless @driver && @driver.respond_to?(:session_id) && @driver.session_id
          Utils.logger.error("Helper não executado: driver nulo ou sessão encerrada.")
          return
        end

        FileUtils.mkdir_p(@output_folder)

        triage_result = Analyzer.triage_error(@exception) rescue :unknown
        platform_value = (@driver.capabilities[:platform_name] rescue nil) || (@driver.capabilities['platformName'] rescue nil)
        platform = platform_value&.downcase || 'unknown'

        report_data = {
          exception: @exception,
          triage_result: triage_result,
          timestamp: @timestamp,
          platform: platform,
          screenshot_base_64: safe_screenshot_base64
        }

        if triage_result == :locator_issue
          page_source = safe_page_source
          # tenta extrair detalhes do Analyzer (se existir), senão usa fetch_failed_element
          failed_info = {}
          begin
            failed_info = Analyzer.extract_failure_details(@exception) if Analyzer.respond_to?(:extract_failure_details)
          rescue
            failed_info = {}
          end

          if failed_info.nil? || failed_info.empty?
            # tenta extrair do próprio handler (regex mais robusta)
            failed_info = fetch_failed_element || {}
          end

          # fallback para extrair do código-fonte (se existir)
          if (failed_info.nil? || failed_info.empty?) && SourceCodeAnalyzer.respond_to?(:extract_from_exception)
            begin
              failed_info = SourceCodeAnalyzer.extract_from_exception(@exception) || {}
            rescue
              failed_info = {}
            end
          end

          # garante que exista ao menos um objeto failed_element
          if failed_info.nil? || failed_info.empty?
            failed_info = { selector_type: 'unknown', selector_value: @exception&.message.to_s }
            report_data[:triage_result] = :unidentified_locator_issue
          end

          all_page_elements = []
          best_candidate_analysis = nil
          alternative_xpaths = []

          if page_source
            begin
              doc = Nokogiri::XML(page_source)
              page_analyzer = PageAnalyzer.new(page_source, platform)
              all_page_elements = page_analyzer.analyze || []
              best_candidate_analysis = Analyzer.perform_advanced_analysis(failed_info, all_page_elements, platform) rescue nil
            rescue => e
              Utils.logger.warn("Erro analisando page_source: #{e.message}")
            end
          end

          # se não encontrou candidato, gera alternativas a partir do locator bruto
          if best_candidate_analysis.nil?
            # tenta parse por Analyzer (se exposto), senão regex fallback
            failed_attrs = {}
            begin
              if Analyzer.respond_to?(:parse_locator) || Analyzer.private_methods.include?(:parse_locator)
                failed_attrs = Analyzer.send(:parse_locator, failed_info[:selector_type], failed_info[:selector_value], platform) rescue {}
              end
            rescue
              failed_attrs = {}
            end

            if failed_attrs.nil? || failed_attrs.empty?
              failed_attrs = parse_attrs_from_locator_string(failed_info[:selector_value] || '')
            end

            if failed_attrs && !failed_attrs.empty?
              temp_doc = Nokogiri::XML::Document.new
              tag = (failed_attrs.delete('tag') || failed_attrs.delete(:tag) || 'element').to_s
              target_node = Nokogiri::XML::Node.new(tag, temp_doc)
              failed_attrs.each { |k, v| target_node[k.to_s] = v.to_s unless k.to_s == 'tag' }
              alternative_xpaths = XPathFactory.generate_for_node(target_node) || []
            end
          else
            # se encontrou candidato, tenta gerar alternativas a partir do node encontrado
            if best_candidate_analysis[:attributes] && (path = best_candidate_analysis[:attributes][:path])
              begin
                doc = Nokogiri::XML(page_source) unless defined?(doc) && doc
                target_node = doc.at_xpath(path) rescue nil
                alternative_xpaths = XPathFactory.generate_for_node(target_node) if target_node
              rescue
                # ignore, já temos best_candidate_analysis
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

        ReportGenerator.new(@output_folder, report_data).generate_all
        Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")

      rescue => e
        Utils.logger.error("Erro fatal na GEM de diagnóstico: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    private

    def safe_screenshot_base64
      @driver.respond_to?(:screenshot_as) ? @driver.screenshot_as(:base64) : nil
    rescue => _
      nil
    end

    def safe_page_source
      return nil unless @driver.respond_to?(:page_source)
      @driver.page_source
    rescue => _
      nil
    end

    def fetch_failed_element
      msg = @exception&.message.to_s

      # 1) tentativa de parse clássico com aspas (mais restritivo)
      if (m = msg.match(/using\s+['"](?<type>[^'"]+)['"]\s+with\s+value\s+['"](?<value>.*?)['"]/m))
        return { selector_type: m[:type], selector_value: m[:value] }
      end

      # 2) fallback: pega anything após 'with value' até o final da linha (remove quotes extras)
      if (m = msg.match(/with\s+value\s+(?<value>.+)$/mi))
        raw = m[:value].strip
        # remove quotes de borda apenas se existirem
        raw = raw[1..-2] if raw.start_with?('"', "'") && raw.end_with?('"', "'")
        # tenta detectar o tipo (xpath, id, accessibility id, css)
        guessed_type = if raw =~ %r{^//|^/}i
                         'xpath'
                       elsif raw =~ /^[a-zA-Z0-9\-_:.]+:/
                         'id'
                       else
                         (msg[/\b(xpath|id|accessibility id|css)\b/i] || 'unknown').downcase
                       end
        return { selector_type: guessed_type, selector_value: raw }
      end

      # 3) outros formatos JSON-like
      if (m = msg.match(/"method"\s*:\s*"([^"]+)"[\s,}].*"selector"\s*:\s*"([^"]+)"/i))
        return { selector_type: m[1], selector_value: m[2] }
      end

      # 4) tentativa simples: pegar primeira ocorrência entre aspas
      if (m = msg.match(/["']([^"']+)["']/))
        maybe_value = m[1]
        guessed_type = msg[/\b(xpath|id|accessibility id|css)\b/i] ? $&.downcase : nil
        return { selector_type: guessed_type || 'unknown', selector_value: maybe_value }
      end

      {}
    end

    def parse_attrs_from_locator_string(selector_value)
      attrs = {}
      return attrs unless selector_value.is_a?(String) && !selector_value.empty?

      selector_value.scan(/@([a-zA-Z0-9\-\:]+)\s*=\s*['"]([^'"]+)['"]/).each do |k, v|
        attrs[k] = v
      end

      if selector_value =~ %r{//\s*([a-zA-Z0-9_\-:]+)}
        attrs['tag'] = $1
      elsif selector_value =~ /^([a-zA-Z0-9_\-:]+)\[/
        attrs['tag'] = $1
      end

      attrs
    end
  end
end
