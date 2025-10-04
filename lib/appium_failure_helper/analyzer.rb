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

      id_key_to_check = (platform.to_s == 'ios') ? 'name' : 'resource-id'
      candidates = all_page_elements.map do |element_on_screen|
        score = 0
        analysis = {}

        if expected_attrs[id_key_to_check]
          actual_id = element_on_screen[:attributes][id_key_to_check]
          distance = DidYouMean::Levenshtein.distance(expected_attrs[id_key_to_check].to_s, actual_id.to_s)
          max_len = [expected_attrs[id_key_to_check].to_s.length, actual_id.to_s.length].max
          similarity = max_len.zero? ? 0 : 1.0 - (distance.to_f / max_len)
          score += 100 * similarity
          analysis[id_key_to_check.to_sym] = { similarity: similarity, expected: expected_attrs[id_key_to_check], actual: actual_id }
        end

        { score: score, name: element_on_screen[:name], attributes: element_on_screen[:attributes], analysis: analysis } if score > 75
      end.compact

      candidates.sort_by { |c| -c[:score] }.first
    end

    private

    def self.parse_locator(type, value, platform)
      attrs = {}
      if platform.to_s == 'ios'
        attrs['name'] = value if type.to_s.include?('id')
      else # Android
        attrs['resource-id'] = value if type.to_s.include?('id')
      end
      if type.to_s == 'xpath'
        value.scan(/@([\w\-]+)='([^']+)'/).each { |match| attrs[match[0]] = match[1] }
      end
      attrs
    end
  end
end