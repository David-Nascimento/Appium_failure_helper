module AppiumFailureHelper
  module Analyzer
    def self.triage_error(exception)
      case exception
      when Selenium::WebDriver::Error::NoSuchElementError,
        Selenium::WebDriver::Error::TimeoutError,
        Selenium::WebDriver::Error::UnknownCommandError,
        defined?(Appium::Core::Wait::TimeoutError) ? Appium::Core::Wait::TimeoutError : nil
        :locator_issue
      when Selenium::WebDriver::Error::ElementNotInteractableError
        :visibility_issue
      when Selenium::WebDriver::Error::StaleElementReferenceError
        :stale_element_issue
      when defined?(RSpec::Expectations::ExpectationNotMetError) ? RSpec::Expectations::ExpectationNotMetError : Class.new
        :assertion_failure
      when NoMethodError, NameError, ArgumentError, TypeError
        :ruby_code_issue
      when Selenium::WebDriver::Error::SessionNotCreatedError, Errno::ECONNREFUSED
        :session_startup_issue
      when Selenium::WebDriver::Error::WebDriverError
        return :app_crash_issue if exception.message.include?('session deleted because of page crash')
        :unknown_appium_issue
      else
        :unknown_issue
      end
    end

    def self.extract_failure_details(exception)
      message = exception.message.to_s
      info = {}
      pattern = /using "([^"]+)" with value "([^"]+)"/
      match = message.match(pattern)
      if match
        info[:selector_type], info[:selector_value] = match.captures
      end
      info
    end

    def self.perform_advanced_analysis(failed_info, all_page_elements, platform)
      return nil if failed_info.empty? || all_page_elements.empty?

      expected_attrs = parse_locator(failed_info[:selector_type], failed_info[:selector_value], platform)
      return nil if expected_attrs.empty?

      id_key = (platform.to_s == 'ios') ? 'name' : 'resource-id'
      candidates = []

      all_page_elements.each do |element_on_screen|
        score = 0
        analysis = {}
        screen_attrs = element_on_screen[:attributes]

        # Compara ID (pontuação máxima)
        if expected_attrs[id_key] && screen_attrs[id_key]
          similarity = calculate_similarity(expected_attrs[id_key], screen_attrs[id_key])
          score += 100 * similarity
          analysis[id_key.to_sym] = { similarity: similarity, expected: expected_attrs[id_key], actual: screen_attrs[id_key] }
        end

        # Compara Texto (pontuação média)
        if expected_attrs['text'] && screen_attrs['text']
          similarity = calculate_similarity(expected_attrs['text'], screen_attrs['text'])
          score += 50 * similarity
          analysis[:text] = { similarity: similarity, expected: expected_attrs['text'], actual: screen_attrs['text'] }
        end

        # Compara Content Description (pontuação alta para Android)
        if expected_attrs['content-desc'] && screen_attrs['content-desc']
          similarity = calculate_similarity(expected_attrs['content-desc'], screen_attrs['content-desc'])
          score += 80 * similarity
          analysis[:'content-desc'] = { similarity: similarity, expected: expected_attrs['content-desc'], actual: screen_attrs['content-desc'] }
        end

        if score > 50 # Limiar mínimo para ser considerado um candidato
          candidates << {
            score: score,
            name: element_on_screen[:name],
            attributes: element_on_screen[:attributes],
            analysis: analysis
          }
        end
      end

      candidates.sort_by { |c| -c[:score] }.first
    end

    private

    def self.parse_locator(type, value, platform)
      attrs = {}
      type = type.to_s.downcase

      if platform.to_s == 'ios'
        attrs['name'] = value if type.include?('id')
      else # Android
        attrs['resource-id'] = value if type.include?('id')
      end

      if type == 'xpath'
        value.scan(/@([\w\-]+)='([^']+)'/).each do |match|
          attrs[match[0]] = match[1]
        end
      end
      attrs
    end
  end
end