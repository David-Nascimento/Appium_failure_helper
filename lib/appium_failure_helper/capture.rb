require 'nokogiri'
require 'fileutils'
require 'base64'
require 'yaml'

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

    def self.handler_failure(driver)
      begin
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        output_folder = "screenshots/failure_#{timestamp}"
        
        FileUtils.mkdir_p(output_folder)
        
        screenshot_path = "#{output_folder}/screenshot_#{timestamp}.png"
        File.open(screenshot_path, 'wb') do |f|
          f.write(Base64.decode64(driver.screenshot_as(:base64)))
        end
        puts "Screenshot saved to #{screenshot_path}"

        page_source = driver.page_source
        xml_path = "#{output_folder}/page_source_#{timestamp}.xml"
        File.write(xml_path, page_source)

        doc = Nokogiri::XML(page_source)

        platform = driver.capabilities['platformName']&.downcase || 'unknown'

        seen_elements = {}
        suggestions = []

        doc.xpath('//*').each do |node|
          next if node.name == 'hierarchy'
          attrs = node.attributes.transform_values(&:value)
          
          unique_key = "#{node.name}|#{attrs['resource-id']}|#{attrs['content-desc']}|#{attrs['text']}"
          
          unless seen_elements[unique_key]
            name = self.suggest_name(node.name, attrs)
            locators = self.xpath_generator(node.name, attrs, platform)
            
            suggestions << { name: name, locators: locators }
            seen_elements[unique_key] = true
          end
        end

        yaml_path = "#{output_folder}/element_suggestions_#{timestamp}.yaml"
        File.open(yaml_path, 'w') do |f|
          f.write(YAML.dump(suggestions))
        end

        puts "Element suggestions saved to #{yaml_path}"
      rescue => e
        puts "Error capturing failure details: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    private
    
    def self.truncate(value)
      return value unless value.is_a?(String)
      value.size > MAX_VALUE_LENGTH ? "#{value[0...MAX_VALUE_LENGTH]}..." : value
    end

    def self.suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'
      name = attrs['content-desc'] || attrs['text'] || attrs['resource-id'] || attrs['label'] || attrs['name'] || 'unknown' || type
      name = truncate(name.strip.gsub(/[^0-9a-z]/, '').split.map(&:capitalize).join)
      "#{pfx}#{name}"
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
      
      # Estratégia 1: Combinação de atributos
      if attrs['resource-id'] && !attrs['resource-id'].empty? && attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'resource_id_and_text', locator: "//#{tag}[@resource-id\"#{attrs['resource-id']}\" and @text=\"#{self.truncate(attrs['text'])}\"]" }
      elsif attrs['resource-id'] && !attrs['resource-id'].empty? && attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'resource_id_and_content_desc', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\" and @content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end

      # Estratégia 2: ID único
      if attrs['resource-id'] && !attrs['resource-id'].empty?
        locators << { strategy: 'resource_id', locator: "//#{tag}[@resource-id=\"#{attrs['resource-id']}\"]" }
      end

      # Estratégia 3: starts-with para IDs dinâmicos
      if attrs['resource-id'] && attrs['resource-id'].include?(':id/')
        id_part = attrs['resource-id'].split(':id/').last
        locators << { strategy: 'starts_with_resource_id', locator: "//#{tag}[starts-with(@resource-id, \"#{id_part}\")]" }
      end

      # Estratégia 4: Texto e content-desc como identificadores
      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'text', locator: "//#{tag}[@text=\"#{self.truncate(attrs['text'])}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'content_desc', locator: "//#{tag}[@content-desc=\"#{self.truncate(attrs['content-desc'])}\"]" }
      end

      # Fallback genérico (sempre adicionado)
      locators << { strategy: 'generic_tag', locator: "//#{tag}" }

      locators
    end

    def self.generate_ios_xpaths(tag, attrs)
      locators = []

      # Estratégia 1: Combinação de atributos
      if attrs['accessibility-id'] && !attrs['accessibility-id'].empty? && attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'accessibility_id_and_label', locator: "//#{tag}[@accessibility-id=\"#{attrs['accessibility-id']}\" and @label=\"#{self.truncate(attrs['label'])}\"]" }
      end

      # Estratégia 2: ID único
      if attrs['accessibility-id'] && !attrs['accessibility-id'].empty?
        locators << { strategy: 'accessibility_id', locator: "//#{tag}[@accessibility-id=\"#{attrs['accessibility-id']}\"]" }
      end

      # Estratégia 3: label, name ou value
      if attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'label', locator: "//#{tag}[@label=\"#{self.truncate(attrs['label'])}\"]" }
      end
      if attrs['name'] && !attrs['name'].empty?
        locators << { strategy: 'name', locator: "//#{tag}[@name=\"#{self.truncate(attrs['name'])}\"]" }
      end

      # Fallback genérico (sempre adicionado)
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
        locators << { strategy: 'text', locator: "//#{tag}[@text=\"#{self.truncate(attrs['text'])}\"]" }
      end

      # Fallback genérico (sempre adicionado)
      locators << { strategy: 'generic_tag', locator: "//#{tag}" }
      
      locators
    end
  end
end