module AppiumFailureHelper
  module Utils
    def self.logger
      @logger ||= begin
        logger = Logger.new(STDOUT)
        logger.level = Logger::INFO
        logger.formatter = proc { |severity, datetime, progname, msg| "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n" }
        logger
      end
    end
    
    def self.truncate(value, max_length = 100)
      return value unless value.is_a?(String)
      value.size > max_length ? "#{value[0...max_length]}..." : value
    end

    def self.normalize_element(el)
      return {} if el.nil?

      # garante que todas as chaves sejam string
      h = el.transform_keys { |k| k.to_s }

      # unifica value/valor
      value = h['value'] || h['valor']
      tipo  = h['tipoBusca'] || h['type']

      {
        'tipoBusca' => tipo,
        'value'     => value
      }
    end
  end
end