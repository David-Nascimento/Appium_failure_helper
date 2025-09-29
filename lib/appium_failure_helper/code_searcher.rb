# lib/appium_failure_helper/code_searcher.rb
module AppiumFailureHelper
  module CodeSearcher
    def self.extract_failure_details(exception)
      message = exception.message
      info = {}
      patterns = [
        /element \("([^"]+)", "([^"]+)"\) could not be found/,
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
      failed_value = failed_info[:selector_value].to_s
      return nil if failed_value.empty?

      logical_name_key = failed_value.gsub(/^#/, '')

      if element_map.key?(logical_name_key)
        return {
          logical_name: logical_name_key,
          correct_locator: element_map[logical_name_key],
          analysis_type: "Busca Direta"
        }
      end

      cleaned_failed_locator = failed_value.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
      
      element_map.each do |name, locator_info|
        mapped_locator = locator_info['valor'].to_s
        cleaned_mapped_locator = mapped_locator.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip

        distance = DidYouMean::Levenshtein.distance(cleaned_failed_locator, cleaned_mapped_locator)
        max_len = [cleaned_failed_locator.length, cleaned_mapped_locator.length].max
        next if max_len.zero?

        similarity_score = 1.0 - (distance.to_f / max_len)

        if similarity_score > 0.85
          return {
            logical_name: name,
            correct_locator: locator_info,
            analysis_type: "Busca Reversa por Similaridade",
            score: similarity_score
          }
        end
      end

      nil
    end
    
    def self.find_similar_locators(failed_info)
      failed_locator_value = failed_info[:selector_value]
      return [] if failed_locator_value.nil? || failed_locator_value.empty?

      cleaned_failed_locator = failed_locator_value.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
      best_matches = []

      # Busca em todos os arquivos .rb na pasta 'features'
      Dir.glob(File.join('features', '**', '*.rb')).each do |file_path|
        next if file_path.include?('gems') # Ignora gems

        begin
          File.foreach(file_path).with_index do |line, line_num|
            # Regex para extrair qualquer valor de string literal de uma linha
            line.scan(/['"]([^'"]+)['"]/).flatten.each do |found_locator|
              cleaned_found_locator = found_locator.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
              next if cleaned_found_locator.length < 5 # Ignora strings curtas

              distance = DidYouMean::Levenshtein.distance(cleaned_failed_locator, cleaned_found_locator)
              max_len = [cleaned_failed_locator.length, cleaned_found_locator.length].max
              next if max_len.zero?

              similarity_score = 1.0 - (distance.to_f / max_len)

              if similarity_score > 0.85
                best_matches << {
                  score: similarity_score,
                  file: file_path,
                  line_number: line_num + 1,
                  code: line.strip,
                  found_locator: found_locator
                }
              end
            end
          end
        rescue ArgumentError # Ignora erros de encoding de arquivos
          next
        end
      end
      
      best_matches.sort_by { |m| -m[:score] }.first(3)
    end
  end
end