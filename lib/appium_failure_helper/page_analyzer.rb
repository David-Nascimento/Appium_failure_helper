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

    CRITICAL_PATTERNS = [
      /resource-id/i,
      /text/i,
      /content-desc/i,
      /login/i,
      /password/i,
      /email/i
    ].freeze

    def initialize(page_source, platform)
      @doc = Nokogiri::XML(page_source)
      @platform = platform
    end

    def analyze
      all_elements_suggestions = []

      @doc.xpath('//*').each do |node|
        next if ['hierarchy', 'AppiumAUT'].include?(node.name)

        # Extrair todos os atributos do node
        attrs = node.attribute_nodes.to_h { |attr| [attr.name, attr.value] }

        # Normalização iOS
        if @platform == 'ios'
          attrs['text'] = attrs['label'] || attrs['value']
          attrs['resource-id'] = attrs['name']
        end

        attrs['tag'] = node.name
        attrs['critical'] = critical_element?(attrs) # flag de criticidade
        name = suggest_name(node.name, attrs)
        locators = xpath_generator(node.name, attrs)

        all_elements_suggestions << { 
          name: name, 
          locators: locators, 
          attributes: attrs.merge(path: node.path)
        }
      end

      # Organiza por criticidade: alto → médio → baixo
      all_elements_suggestions.sort_by do |el|
        el[:attributes][:critical] ? 0 : 1
      end
    end

    private

    def critical_element?(attrs)
      CRITICAL_PATTERNS.any? { |regex| attrs.any? { |k,v| v.to_s.match?(regex) } }
    end

    def suggest_name(tag, attrs)
      type = tag.split('.').last
      pfx = PREFIX[tag] || PREFIX[type] || 'elm'

      priority_attrs = if tag.start_with?('XCUIElementType')
                         ['name', 'label', 'value']
                       else
                         ['resource-id', 'content-desc', 'text']
                       end

      name_base = priority_attrs.map { |k| attrs[k] }.compact.find { |v| !v.to_s.empty? }
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
      locators << { strategy: 'id', locator: attrs['resource-id'] } if attrs['resource-id']&.strip&.length.to_i > 0
      locators << { strategy: 'xpath', locator: "//#{tag}[@text=\"#{Utils.truncate(attrs['text'])}\"]" } if attrs['text']&.strip&.length.to_i > 0
      locators << { strategy: 'xpath_desc', locator: "//#{tag}[@content-desc=\"#{Utils.truncate(attrs['content-desc'])}\"]" } if attrs['content-desc']&.strip&.length.to_i > 0
      locators
    end

    def generate_ios_xpaths(tag, attrs)
      locators = []
      locators << { strategy: 'name', locator: attrs['name'] } if attrs['name']&.strip&.length.to_i > 0
      locators << { strategy: 'xpath', locator: "//#{tag}[@label=\"#{Utils.truncate(attrs['label'])}\"]" } if attrs['label']&.strip&.length.to_i > 0
      locators
    end

    def generate_unknown_xpaths(tag, attrs)
      attrs.map do |k,v|
        { strategy: k.to_s, locator: "//#{tag}[@#{k}=\"#{Utils.truncate(v)}\"]" } if v.is_a?(String) && !v.empty?
      end.compact
    end
  end
end
