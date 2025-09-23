require 'nokogiri'
require 'fileutils'
require 'base64'
require 'yaml'
require 'logger'

module AppiumFailureHelper
  class Capture
    PREFIX = {
      'android.widget.Button' => 'btn',
      'android.widget.TextView' => 'txt',
      'android.widget.ImageView' => 'img',
      'android.widget.EditText' => 'input',
      'android.widget.CheckBox' => 'chk',
      'android.widget.RadioButton' => 'radio',
      'android.widget.Switch' => 'switch',
      'android.widget.ViewGroup' => 'group',
      'android.widget.View' => 'view',
      'android.widget.FrameLayout' => 'frame',
      'android.widget.LinearLayout' => 'linear',
      'android.widget.RelativeLayout' => 'relative',
      'android.widget.ScrollView' => 'scroll',
      'android.webkit.WebView' => 'web',
      'android.widget.Spinner' => 'spin',
      'XCUIElementTypeButton' => 'btn',
      'XCUIElementTypeStaticText' => 'txt',
      'XCUIElementTypeTextField' => 'input',
      'XCUIElementTypeImage' => 'img',
      'XCUIElementTypeSwitch' => 'switch',
      'XCUIElementTypeScrollView' => 'scroll',
      'XCUIElementTypeOther' => 'elm',
      'XCUIElementTypeCell' => 'cell',
    }.freeze
    
    MAX_VALUE_LENGTH = 100
    @@logger = nil

    def self.handler_failure(driver, exception)
      begin
        self.setup_logger unless @@logger
        
        # Remove a pasta reports_failure ao iniciar uma nova execução
        FileUtils.rm_rf("reports_failure")
        @@logger.info("Pasta 'reports_failure' removida para uma nova execução.")
        
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        output_folder = "reports_failure/failure_#{timestamp}"
        
        FileUtils.mkdir_p(output_folder)
        @@logger.info("Pasta de saída criada: #{output_folder}")
        
        screenshot_path = "#{output_folder}/screenshot_#{timestamp}.png"
        File.open(screenshot_path, 'wb') do |f|
          f.write(Base64.decode64(driver.screenshot_as(:base64)))
        end
        @@logger.info("Screenshot salvo em #{screenshot_path}")

        page_source = driver.page_source
        xml_path = "#{output_folder}/page_source_#{timestamp}.xml"
        File.write(xml_path, page_source)
        @@logger.info("Page source salvo em #{xml_path}")

        doc = Nokogiri::XML(page_source)
        platform = driver.capabilities['platformName']&.downcase || 'unknown'

        failed_element_info = self.extract_info_from_exception(exception)

        # --- Processamento de todos os elementos ---
        seen_elements = {}
        all_elements_suggestions = []
        doc.xpath('//*').each do |node|
          next if node.name == 'hierarchy'
          attrs = node.attributes.transform_values(&:value)
          
          unique_key = "#{node.name}|#{attrs['resource-id'].to_s}|#{attrs['content-desc'].to_s}|#{attrs['text'].to_s}"
          
          unless seen_elements[unique_key]
            name = self.suggest_name(node.name, attrs)
            locators = self.xpath_generator(node.name, attrs, platform)
            
            all_elements_suggestions << { name: name, locators: locators }
            seen_elements[unique_key] = true
          end
        end

        # --- Geração do Relatório FOCADO (1) ---
        targeted_report = {
          failed_element: failed_element_info,
          similar_elements: [],
        }

        if failed_element_info && failed_element_info[:selector_value]
          targeted_report[:similar_elements] = self.find_similar_elements(doc, failed_element_info, platform)
        end
        
        targeted_yaml_path = "#{output_folder}/failure_analysis_#{timestamp}.yaml"
        File.open(targeted_yaml_path, 'w') do |f|
          f.write(YAML.dump(targeted_report))
        end
        @@logger.info("Análise direcionada salva em #{targeted_yaml_path}")

        # --- Geração do Relatório COMPLETO (2) ---
        full_dump_yaml_path = "#{output_folder}/all_elements_dump_#{timestamp}.yaml"
        File.open(full_dump_yaml_path, 'w') do |f|
          f.write(YAML.dump(all_elements_suggestions))
        end
        @@logger.info("Dump completo da página salvo em #{full_dump_yaml_path}")

      rescue => e
        @@logger.error("Erro ao capturar detalhes da falha: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    private
    
    def self.setup_logger
      @@logger = Logger.new(STDOUT)
      @@logger.level = Logger::INFO
      @@logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
      end
    end
    
    def self.extract_info_from_exception(exception)
      message = exception.message
      info = {}
      
      patterns = [
        /(?:could not be found|cannot find element) using (.+)=['"](.+)['"]/i,
        /no such element: Unable to locate element: {"method":"([^"]+)","selector":"([^"]+)"}/i
      ]
      
      patterns.each do |pattern|
        match = message.match(pattern)
        if match
          selector_type = match[1].strip
          selector_value = match[2].strip
          
          info[:selector_type] = selector_type
          info[:selector_value] = selector_value.gsub(/['"]/, '')
          return info
        end
      end
      info
    end

    def self.find_similar_elements(doc, failed_info, platform)
      similar_elements = []
      doc.xpath('//*').each do |node|
        next if node.name == 'hierarchy'
        attrs = node.attributes.transform_values(&:value)
        
        is_similar = case platform
        when 'android'
          (attrs['resource-id']&.include?(failed_info[:selector_value]) ||
           attrs['text']&.include?(failed_info[:selector_value]) ||
           attrs['content-desc']&.include?(failed_info[:selector_value]))
        when 'ios'
          (attrs['accessibility-id']&.include?(failed_info[:selector_value]) ||
           attrs['label']&.include?(failed_info[:selector_value]) ||
           attrs['name']&.include?(failed_info[:selector_value]))
        else
          false
        end

        if is_similar
          name = self.suggest_name(node.name, attrs)
          locators = self.xpath_generator(node.name, attrs, platform)
          similar_elements << { name: name, locators: locators }
        end
      end
      similar_elements
    end
    
    def self.truncate(value)
      return value unless value.is_a?(String)
      value.size > MAX_VALUE_LENGTH ? "#{value[0...MAX_VALUE_LENGTH]}..." : value
    end

    def self.suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'
      name_base = nil
      
      ['content-desc', 'text', 'resource-id', 'label', 'name'].each do |attr_key|
        value = attrs[attr_key]
        if value.is_a?(String) && !value.empty?
          name_base = value
          break
        end
      end
      
      name_base ||= type
      
      truncated_name = truncate(name_base)
      sanitized_name = truncated_name.gsub(/[^a-zA-Z0-9\s]/, ' ').split.map(&:capitalize).join
      
      "#{pfx}#{sanitized_name}"
    end

    def self.xpath_generator(tag, attrs, platform)
      case platform
      when 'android'
        self.generate_android_xpaths(tag, attrs)
      when 'ios'
        self.generate_ios_xpaths(tag, attrs)
      else
        self.generate_unknown_xpaths(tag, attrs)
      end
    end

    def self.generate_android_xpaths(tag, attrs)
      locators = []
      
      if attrs['resource-id'] && !attrs['resource-id'].empty? && attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'resource_id_and_text', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\" and @text=\"#{self.truncate(attrs['text'])}\"]" }
      elsif attrs['resource-id'] && !attrs['resource-id'].empty? && attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'resource_id_and_content_desc', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\" and @content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end

      if attrs['resource-id'] && !attrs['resource-id'].empty?
        locators << { strategy: 'resource_id', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\"]" }
      end

      if attrs['resource-id'] && attrs['resource-id'].include?(':id/')
        id_part = attrs['resource-id'].split(':id/').last
        locators << { strategy: 'starts_with_resource_id', locator: "//#{tag}[starts-with(@resource-id, \"#{id_part}\")]" }
      end

      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'text', locator: "//#{tag}[@text=\"#{self.truncate(attrs['text'])}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'content_desc', locator: "//#{tag}[@content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end

      locators << { strategy: 'generic_tag', locator: "//#{tag}" }

      locators
    end

    def self.generate_ios_xpaths(tag, attrs)
      locators = []

      if attrs['accessibility-id'] && !attrs['accessibility-id'].empty? && attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'accessibility_id_and_label', locator: "//#{tag}[@accessibility-id=\"#{attrs['accessibility-id']}\" and @label=\"#{self.truncate(attrs['label'])}']" }
      end

      if attrs['accessibility-id'] && !attrs['accessibility-id'].empty?
        locators << { strategy: 'accessibility_id', locator: "//#{tag}[@accessibility-id=\"#{attrs['accessibility-id']}\"]" }
      end

      if attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'label', locator: "//#{tag}[@label=\"#{self.truncate(attrs['label'])}\"]" }
      end
      if attrs['name'] && !attrs['name'].empty?
        locators << { strategy: 'name', locator: "//#{tag}[@name=\"#{self.truncate(attrs['name'])}\"]" }
      end

      locators << { strategy: 'generic_tag', locator: "//#{tag}" }

      locators
    end

    def self.generate_unknown_xpaths(tag, attrs)
      locators = []
      if attrs['resource-id'] && !attrs['resource-id'].empty?
        locators << { strategy: 'resource_id', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'content_desc', locator: "//#{tag}[@content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end
      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'text', locator: "//#{tag}[@text=\"#{self.truncate(attrs['text'])}']" }
      end

      locators << { strategy: 'generic_tag', locator: "//#{tag}" }
      
      locators
    end
  end
end
