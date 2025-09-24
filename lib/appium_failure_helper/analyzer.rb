module AppiumFailureHelper
  module Analyzer
    def self.extract_failure_details(exception)
      message = exception.message
      info = {}
      patterns = [
        /element with locator ['"]?(#?\w+)['"]?/i,
        /(?:could not be found|cannot find element) using (.+?)=['"]?([^'"]+)['"]?/i,
        /no such element: Unable to locate element: {"method":"([^"]+)","selector":"([^"]+)"}/i,
        /(?:with the resource-id|with the accessibility-id) ['"]?(.+?)['"]?/i
      ]
      patterns.each do |pattern|
          match = message.match(pattern)
          if match
              info[:selector_value] = match.captures.last.strip.gsub(/['"]/, '')
              info[:selector_type] = match.captures.size > 1 ? match.captures[0].strip.gsub(/['"]/, '') : 'id'
              return info
          end
      end
      info
    end

    def self.find_de_para_match(failed_info, element_map)
      logical_name_key = failed_info[:selector_value].to_s.gsub(/^#/, '')
      if element_map.key?(logical_name_key)
        return {
          logical_name: logical_name_key,
          correct_locator: element_map[logical_name_key]
        }
      end
      nil
    end

    def self.find_similar_elements(failed_info, all_page_suggestions)
      failed_locator_value = failed_info[:selector_value]
      failed_locator_type = failed_info[:selector_type]
      return [] unless failed_locator_value && failed_locator_type

      normalized_failed_type = failed_locator_type.downcase.include?('id') ? 'id' : failed_locator_type

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
        if similarity_score > 0.8
          similarities << { name: suggestion[:name], locators: suggestion[:locators], score: similarity_score }
        end
      end
      similarities.sort_by { |s| -s[:score] }.first(5)
    end
  end
end