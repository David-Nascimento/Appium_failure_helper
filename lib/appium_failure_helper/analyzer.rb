module AppiumFailureHelper
  module Analyzer
    def self.triage_error(exception)
      # Simples e direto: se for um desses erros, é um problema de seletor.
      if exception.is_a?(Selenium::WebDriver::Error::NoSuchElementError) || exception.is_a?(Selenium::WebDriver::Error::TimeoutError)
        :locator_issue
      else
        :generic_issue # Para todos os outros casos
      end
    end

    def self.extract_failure_details(exception)
      message = exception.message
      info = {}
      # único padrão que precisa, para ler a mensagem enriquecida
      pattern = /using "([^"]+)" with value "([^"]+)"/
      
      match = message.match(pattern)
      if match
        info[:selector_type] = match.captures[0]
        info[:selector_value] = match.captures[1]
      end
      info
    end

    def self.find_de_para_match(failed_info, element_map)
      failed_value = failed_info[:selector_value].to_s
      return nil if failed_value.empty?
      logical_name_key = failed_value.gsub(/^#/, '')
      if element_map.key?(logical_name_key)
        return { logical_name: logical_name_key, correct_locator: element_map[logical_name_key] }
      end
      cleaned_failed_locator = failed_value.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
      element_map.each do |name, locator_info|
        mapped_locator = locator_info['valor'].to_s || locator_info['value'].to_s
        cleaned_mapped_locator = mapped_locator.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
        distance = DidYouMean::Levenshtein.distance(cleaned_failed_locator, cleaned_mapped_locator)
        max_len = [cleaned_failed_locator.length, cleaned_mapped_locator.length].max
        next if max_len.zero?
        similarity_score = 1.0 - (distance.to_f / max_len)
        if similarity_score > 0.85
          return { logical_name: name, correct_locator: locator_info }
        end
      end
      nil
    end

    def self.find_similar_elements(failed_info, all_page_suggestions)
      failed_locator_value = failed_info[:selector_value]
      failed_locator_type = failed_info[:selector_type]
      return [] unless failed_locator_value && failed_locator_type
      normalized_failed_type = failed_locator_type.to_s.downcase.include?('id') ? 'id' : failed_locator_type.to_s
      cleaned_failed_locator = failed_locator_value.to_s.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
      similarities = []
      all_page_suggestions.each do |suggestion|
        candidate_locator = suggestion[:locators].find { |loc| loc[:strategy] == normalized_failed_type }
        next unless candidate_locator
        cleaned_candidate_locator = candidate_locator[:locator].gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
        distance = DidYouMean::Levenshtein.distance(cleaned_failed_locator, cleaned_candidate_locator)
        max_len = [cleaned_failed_locator.length, cleaned_candidate_locator.length].max
        next if max_len.zero?
        similarity_score = 1.0 - (distance.to_f / max_len)
        if similarity_score > 0.85
          similarities << { name: suggestion[:name], locators: suggestion[:locators], score: similarity_score, attributes: suggestion[:attributes] }
        end
      end
      similarities.sort_by { |s| -s[:score] }.first(5)
    end
  end
end