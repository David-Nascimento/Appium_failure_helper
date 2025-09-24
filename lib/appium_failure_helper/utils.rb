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
  end
end