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

        yaml_path = "#{output_folder}/element_suggestions_#{timestamp}.yaml"
        File.open(yaml_path, 'w') do |f|
          suggestions = doc.xpath('//*').map do |node|
            next if node.name == 'hierarchy'
            attrs = node.attributes.transform_values(&:value)
            
            name = self.suggest_name(node.name, attrs)
            xpath = self.xpath_generator(node.name, attrs, platform)

            parent_node = node.parent
            parent_xpath = parent_node ? parent_node.path : nil
            
            { 
              name: name, 
              type: 'xpath', 
              locator: xpath,
              parent_locator: parent_xpath
            }
          end.compact

          f.write(YAML.dump(suggestions))
        end

        puts "Element suggestions saved to #{yaml_path}"
      rescue => e
        puts "Error capturing failure details: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    private
    
    def self.suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'
      name = attrs['content-desc'] || attrs['text'] || attrs['resource-id'] || attrs['label'] || attrs['name'] || 'unknown' || type
      name = name.strip.gsub(/[^0-9a-z]/, '').split.map(&:capitalize).join
      "#{pfx}#{name}"
    end

    def self.xpath_generator(tag, attrs, platform)
      case platform
      when 'android'
        self.generate_android_xpath(tag, attrs)
      when 'ios'
        self.generate_ios_xpath(tag, attrs)
      else
        self.generate_unknown_xpath(tag, attrs)
      end
    end

    def self.generate_android_xpath(tag, attrs)
      strategies = [
        # Estratégia 1: Combinação de resource-id e text/content-desc
        -> {
          if attrs['resource-id'] && !attrs['resource-id'].empty?
            if attrs['text'] && !attrs['text'].empty?
              return "//#{tag}[@resource-id='#{attrs['resource-id']}' and @text='#{attrs['text']}']"
            elsif attrs['content-desc'] && !attrs['content-desc'].empty?
              return "//#{tag}[@resource-id='#{attrs['resource-id']}' and @content-desc='#{attrs['content-desc']}']"
            end
          end
          nil
        },
        # Estratégia 2: resource-id único
        -> { "//#{tag}[@resource-id='#{attrs['resource-id']}']" if attrs['resource-id'] && !attrs['resource-id'].empty? },
        # Estratégia 3: starts-with para resource-id dinâmico
        -> {
          if attrs['resource-id'] && attrs['resource-id'].include?(':id/')
            id_part = attrs['resource-id'].split(':id/').last
            return "//#{tag}[starts-with(@resource-id, '#{id_part}')]"
          end
          nil
        },
        # Estratégia 4: text como identificador
        -> { "//#{tag}[@text='#{attrs['text']}']" if attrs['text'] && !attrs['text'].empty? },
        # Estratégia 5: content-desc como identificador
        -> { "//#{tag}[@content-desc='#{attrs['content-desc']}']" if attrs['content-desc'] && !attrs['content-desc'].empty? },
        # Estratégia 6: Fallback genérico
        -> { "//#{tag}" }
      ]

      strategies.each do |strategy|
        result = strategy.call
        return result if result
      end
    end

    def self.generate_ios_xpath(tag, attrs)
      strategies = [
        # Estratégia 1: Combinação de accessibility-id e label
        -> {
          if attrs['accessibility-id'] && !attrs['accessibility-id'].empty?
            if attrs['label'] && !attrs['label'].empty?
              return "//#{tag}[@accessibility-id='#{attrs['accessibility-id']}' and @label='#{attrs['label']}']"
            end
          end
          nil
        },
        # Estratégia 2: accessibility-id como identificador
        -> { "//#{tag}[@accessibility-id='#{attrs['accessibility-id']}']" if attrs['accessibility-id'] && !attrs['accessibility-id'].empty? },
        # Estratégia 3: label como identificador
        -> { "//#{tag}[@label='#{attrs['label']}']" if attrs['label'] && !attrs['label'].empty? },
        # Estratégia 4: name como identificador
        -> { "//#{tag}[@name='#{attrs['name']}']" if attrs['name'] && !attrs['name'].empty? },
        # Estratégia 5: Fallback genérico
        -> { "//#{tag}" }
      ]

      strategies.each do |strategy|
        result = strategy.call
        return result if result
      end
    end

    def self.generate_unknown_xpath(tag, attrs)
      if attrs['resource-id'] && !attrs['resource-id'].empty?
        "//#{tag}[@resource-id='#{attrs['resource-id']}']"
      elsif attrs['content-desc'] && !attrs['content-desc'].empty?
        "//#{tag}[@content-desc='#{attrs['content-desc']}']"
      elsif attrs['text'] && !attrs['text'].empty?
        "//#{tag}[@text='#{attrs['text']}']"
      else
        "//#{tag}"
      end
    end
  end
end
