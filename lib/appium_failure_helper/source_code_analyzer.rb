# lib/appium_failure_helper/source_code_analyzer.rb
module AppiumFailureHelper
  module SourceCodeAnalyzer
    PATTERNS = [
      { type: 'id',               regex: /find_element\((?:id:|:id\s*=>)\s*['"]([^'"]+)['"]\)/ },
      { type: 'xpath',            regex: /find_element\((?:xpath:|:xpath\s*=>)\s*['"]([^'"]+)['"]\)/ },
      { type: 'accessibility_id', regex: /find_element\((?:accessibility_id:|:accessibility_id\s*=>)\s*['"]([^'"]+)['"]\)/ },
      { type: 'class_name',       regex: /find_element\((?:class_name:|:class_name\s*=>)\s*['"]([^'"]+)['"]\)/ },
      { type: 'xpath',            regex: /find_element\(:xpath,\s*['"]([^'"]+)['"]\)/ },
      { type: 'id',               regex: /\s(?:id)\s*\(?['"]([^'"]+)['"]\)?/ },
      { type: 'xpath',            regex: /\s(?:xpath)\s*\(?['"]([^'"]+)['"]\)?/ },
      { type: 'accessibility_id', regex: /\s(?:accessibility_id)\s*\(?['"]([^'"]+)['"]\)?/ }
    ].freeze

    def self.extract_from_exception(exception)
      location = exception.backtrace.find { |line| line.include?('.rb') && !line.include?('gems') }
      return {} unless location

      path_match = location.match(/^(.*?):(\d+)(?::in.*)?$/)
      return {} unless path_match

      file_path = path_match[1]
      line_number = path_match[2]
      
      return {} unless File.exist?(file_path)

      begin
        error_line = File.readlines(file_path)[line_number.to_i - 1]
        return parse_line_for_locator(error_line)
      rescue
        return {}
      end
    end

    def self.parse_line_for_locator(line)
      PATTERNS.each do |pattern_info|
        match = line.match(pattern_info[:regex])
        if match
          return {
            selector_type: pattern_info[:type].to_s,
            selector_value: match[1],
            analysis_method: "Análise de Código-Fonte"
          }
        end
      end
      {}
    end
  end
end