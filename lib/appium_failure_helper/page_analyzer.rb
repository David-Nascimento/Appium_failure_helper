module AppiumFailureHelper
  class PageAnalyzer
    PREFIX = {
      'android.widget.Button' => 'btn', 'android.widget.TextView' => 'txt',
      'android.widget.ImageView' => 'img', 'android.widget.EditText' => 'input',
      'android.widget.CheckBox' => 'chk', 'android.widget.RadioButton' => 'radio',
      'android.widget.Switch' => 'switch', 'android.widget.ViewGroup' => 'group',
      'android.widget.View' => 'view', 'android.widget.FrameLayout' => 'frame',
      'android.widget.LinearLayout' => 'linear', 'android.widget.RelativeLayout' => 'relative',
      'android.widget.ScrollView' => 'scroll', 'android.webkit.WebView' => 'web',
      'android.widget.Spinner' => 'spin', 'XCUIElementTypeButton' => 'btn',
      'XCUIElementTypeStaticText' => 'txt', 'XCUIElementTypeTextField' => 'input',
      'XCUIElementTypeImage' => 'img', 'XCUIElementTypeSwitch' => 'switch',
      'XCUIElementTypeScrollView' => 'scroll', 'XCUIElementTypeOther' => 'elm',
      'XCUIElementTypeCell' => 'cell'
    }.freeze

    def initialize(page_source, platform)
      @doc = Nokogiri::XML(page_source)
      @platform = platform
    end

     def analyze
      seen_elements = {}
      all_elements_suggestions = []
      @doc.xpath('//*').each do |node|
          next if ['hierarchy', 'AppiumAUT'].include?(node.name)
          attrs = node.attributes.transform_values(&:value)
          
          unique_key = node.path
          next if seen_elements[unique_key]

          name = suggest_name(node.name, attrs)
          
          locators = XPathFactory.generate_for_node(node)
          
         all_elements_suggestions << { 
            name: name, 
            locators: locators, 
            attributes: attrs.merge(tag: node.name, path: node.path) 
          }
          seen_elements[unique_key] = true
      end
      all_elements_suggestions
    end

    private

    def suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'
      name_base = nil
      
      priority_attrs = if tag.start_with?('XCUIElementType')
                         ['name', 'label', 'value']
                       else
                         ['content-desc', 'text', 'resource-id']
                       end

      priority_attrs.each do |attr_key|
        value = attrs[attr_key]
        if value.is_a?(String) && !value.empty?
          name_base = value
          break
        end
      end
      
      name_base ||= type.gsub('XCUIElementType', '')
      
      truncated_name = Utils.truncate(name_base)
      sanitized_name = truncated_name.gsub(/[^a-zA-Z0-9\s]/, ' ').split.map(&:capitalize).join
      
      "#{pfx}#{sanitized_name}"
    end

    def xpath_generator(tag, attrs)
      case @platform
      when 'android' then generate_android_xpaths(tag, attrs)
      when 'ios' then generate_ios_xpaths(tag, attrs)
      else generate_unknown_xpaths(tag, attrs)
      end
    end

    def generate_android_xpaths(tag, attrs)
      locators = []
      if attrs['resource-id'] && !attrs['resource-id'].empty?
        locators << { strategy: 'id', locator: attrs['resource-id'] }
      end
      if attrs['text'] && !attrs['text'].empty?
        locators << { strategy: 'xpath', locator: "//#{tag}[@text=\"#{Utils.truncate(attrs['text'])}\"]" }
      end
      if attrs['content-desc'] && !attrs['content-desc'].empty?
        locators << { strategy: 'xpath_desc', locator: "//#{tag}[@content-desc=\"#{Utils.truncate(attrs['content-desc'])}\"]" }
      end
      locators
    end

    def generate_ios_xpaths(tag, attrs)
      locators = []
      if attrs['name'] && !attrs['name'].empty?
        locators << { strategy: 'name', locator: attrs['name'] }
      end
      if attrs['label'] && !attrs['label'].empty?
        locators << { strategy: 'xpath', locator: "//#{tag}[@label=\"#{Utils.truncate(attrs['label'])}\"]" }
      end
      locators
    end
    
    def generate_unknown_xpaths(tag, attrs)
      locators = []
      attrs.each { |key, value| locators << { strategy: key.to_s, locator: "//#{tag}[@#{key}=\"#{Utils.truncate(value)}\"]" } if value.is_a?(String) && !value.empty? }
      locators
    end
  end
end