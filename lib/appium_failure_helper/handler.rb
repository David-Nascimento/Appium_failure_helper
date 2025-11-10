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

        page_source = safe_page_source
        failed_info = fetch_failed_element || {}

        # Extrai todos os elementos da tela
        all_page_elements = []
        if page_source
          begin
            if defined?(DumpParser) && DumpParser.respond_to?(:parse)
              all_page_elements = DumpParser.parse(page_source) || []
            elsif defined?(Dump) && Dump.respond_to?(:from_xml)
              all_page_elements = Dump.from_xml(page_source) || []
            else
              require 'nokogiri' unless defined?(Nokogiri)
              doc = Nokogiri::XML(page_source) rescue nil
              if doc
                all_page_elements = doc.xpath('//*').map do |node|
                  { name: node.name, attributes: node.attributes.transform_values(&:value).merge('tag' => node.name) }
                end
              end
            end
          rescue => e
            Utils.logger.warn("Falha ao extrair elementos do page_source: #{e.message}")
            all_page_elements = []
          end
        end

        # Executa análise avançada se houver failed_info
        best_candidate_analysis = if failed_info.empty?
                                    # Fallback: gerar análise heurística mesmo sem failed_info
                                    all_page_elements.map do |elm|
                                      {
                                        score: 0,
                                        name: elm[:name],
                                        attributes: elm[:attributes],
                                        analysis: {}
                                      }
                                    end.first(3)
                                  else
                                    Analyzer.perform_advanced_analysis(failed_info, all_page_elements, platform) rescue nil
                                  end

        # Gera alternativas de XPath mesmo sem failed_info
        tag_for_factory = nil
        attrs_for_factory = nil
        if best_candidate_analysis&.any?
          first_candidate = best_candidate_analysis.first
          attrs = first_candidate[:attributes] || {}
          tag_for_factory = attrs['tag'] || first_candidate[:name]
          attrs_for_factory = attrs
        end
        alternative_xpaths = XPathFactory.generate_for_node(tag_for_factory, attrs_for_factory) if tag_for_factory && attrs_for_factory

        report_data.merge!(
          page_source: page_source,
          failed_element: failed_info,
          best_candidate_analysis: best_candidate_analysis,
          alternative_xpaths: alternative_xpaths,
          all_page_elements: all_page_elements
        )

        # Gera relatório
        report_generator = ReportGenerator.new(@output_folder, report_data)
        generated_html_path = report_generator.generate_all
        copy_report_for_ci(generated_html_path)

        Utils.logger.info("Relatórios gerados com sucesso em: #{@output_folder}")

      rescue => e
        Utils.logger.error("Erro fatal na GEM de diagnóstico: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    private

    def safe_screenshot_base64
      @driver.respond_to?(:screenshot_as) ? @driver.screenshot_as(:base64) : nil
    rescue
      nil
    end

    def safe_page_source
      return nil unless @driver.respond_to?(:page_source)
      @driver.page_source
    rescue
      nil
    end

    def fetch_failed_element
      msg = @exception&.message.to_s

      if (m = msg.match(/using\s+['"](?<type>[^'"]+)['"]\s+with\s+value\s+['"](?<value>.*?)['"]/m))
        return { selector_type: m[:type], selector_value: m[:value] }
      end

      if (m = msg.match(/with\s+value\s+(?<value>.+)$/mi))
        raw = m[:value].strip
        raw = raw[1..-2] if raw.start_with?('"', "'") && raw.end_with?('"', "'")
        guessed_type = if raw =~ %r{^//|^/}i
                         'xpath'
                       elsif raw =~ /^[a-zA-Z0-9\-_:.]+:/
                         'id'
                       else
                         (msg[/\b(xpath|id|accessibility id|css)\b/i] || 'unknown').downcase
                       end
        return { selector_type: guessed_type, selector_value: raw }
      end

      if (m = msg.match(/"method"\s*:\s*"([^"]+)"[\s,}].*"selector"\s*:\s*"([^"]+)"/i))
        return { selector_type: m[1], selector_value: m[2] }
      end

      if (m = msg.match(/["']([^"']+)["']/))
        maybe_value = m[1]
        guessed_type = msg[/\b(xpath|id|accessibility id|css)\b/i] ? $&.downcase : 'unknown'
        return { selector_type: guessed_type || 'unknown', selector_value: maybe_value }
      end

      {}
    end

    def copy_report_for_ci(source_html_path)
      return unless source_html_path && File.exist?(source_html_path)

      ci_report_dir = File.join(Dir.pwd, 'ci_failure_report')
      FileUtils.mkdir_p(ci_report_dir)

      destination_path = File.join(ci_report_dir, 'index.html')
      FileUtils.cp(source_html_path, destination_path)
      Utils.logger.info("Relatório copiado para CI em: #{destination_path}")
    rescue => e
      Utils.logger.warn("AVISO: Falha ao copiar relatório para CI. Erro: #{e.message}")
    end
  end
end
