module AppiumFailureHelper
  module CodeSearcher
    def self.find_similar_locators(failed_info)
      failed_locator_value = failed_info[:selector_value]
      return [] if failed_locator_value.nil? || failed_locator_value.empty?

      cleaned_failed_locator = failed_locator_value.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
      best_matches = []

      Dir.glob(File.join('features', '**', '*.rb')).each do |file_path|
        next if file_path.include?('gems')

        begin
          File.foreach(file_path).with_index do |line, line_num|
            line.scan(/['"]([^'"]+)['"]/).flatten.each do |found_locator|
              cleaned_found_locator = found_locator.gsub(/[:\-\/@=\[\]'"()]/, ' ').gsub(/\s+/, ' ').downcase.strip
              next if cleaned_found_locator.length < 5

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
        rescue ArgumentError
          next
        end
      end
      
      best_matches.sort_by { |m| -m[:score] }.first(3)
    end
  end
end