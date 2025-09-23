require 'nokogiri'
require 'fileutils'
require 'base64'

module AppiumFailureHelper
  class Capture
    def self.handler_failure(driver)
      begin
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        folder_path = "screenshots"
        
        # Lógica melhorada para criar a pasta.
        # O método mkdir_p cria a pasta apenas se ela não existir,
        # tornando a verificação Dir.exist? desnecessária.
        FileUtils.mkdir_p(folder_path)
        
        screenshot_path = "#{folder_path}/screenshot_#{timestamp}.png"
        File.open(screenshot_path, 'wb') do |f|
          f.write(Base64.decode64(driver.screenshot_as(:base64)))
        end
        puts "Screenshot saved to #{screenshot_path}"

        page_source = driver.page_source
        xml_path = "#{folder_path}/page_source_#{timestamp}.xml"
        File.write(xml_path, page_source)

        doc = Nokogiri::XML(page_source)

        prefix = {
          'Button' => 'btn',
          'TextView' => 'txt',
          'ImageView' => 'img',
          'EditText' => 'input',
          'CheckBox' => 'chk',
          'RadioButton' => 'radio',
          'Switch' => 'switch',
        }

        def suggest_name(tag, attrs, prefix)
          type = tag.split('.').last
          pfx = prefix[type] || 'elm'
          name = attrs['content-desc'] || attrs['text'] || attrs['resource-id'] || 'unknown' || type
          name = name.strip.gsub(/[^0-9a-z]/, '').split.map(&:capitalize).join
          "#{pfx}#{name}"
        end

        def xpath_generator(tag, attrs)
          type = tag.split('.').last
          if attrs['resource-id'] && !attrs['resource-id'].empty?
            "//*[@resource-id='#{attrs['resource-id']}']"
          elsif attrs['content-desc'] && !attrs['content-desc'].empty?
            "//*[@content-desc='#{attrs['content-desc']}']"
          elsif attrs['text'] && !attrs['text'].empty?
            "//*[@text='#{attrs['text']}']"
          else
            "//#{type}"
          end
        end

        line = doc.xpath('//*').map do |node|
          next if node.name == 'hierarchy'
          attrs = node.attributes.transform_values(&:value)
          name = suggest_name(node.name, attrs, prefix)
          xpath = xpath_generator(node.name, attrs)
          "[\"#{name}\", \"xpath\", \"#{xpath}\"]"
        end

        yaml_path = "#{folder_path}/element_suggestions_#{timestamp}.yaml"
        File.open(yaml_path, 'w') {|f| f.puts(line.compact.join("\n"))}

        puts "Element suggestions saved to #{yaml_path}"
      rescue => e
        puts "Error capturing failure details: #{e.message}"
      end
    end
  end
end
