require_relative 'test_helper'

class TestXPathFactory < Minitest::Test
  def test_generate_for_node_creates_multiple_strategies
    xml_string = '<hierarchy><android.widget.EditText text="Email" resource-id="com.app:id/email_field"/></hierarchy>'
    doc = Nokogiri::XML(xml_string)
    node = doc.at_xpath('//android.widget.EditText')
    
    strategies = AppiumFailureHelper::XPathFactory.generate_for_node(node)
    
    assert strategies.size > 3 # Deve gerar várias estratégias
    
    # Verifica se a estratégia de ID (a mais importante) foi gerada corretamente
    id_strategy = strategies.find { |s| s[:strategy] == 'id' }
    assert_not_nil id_strategy
    assert_equal 'com.app:id/email_field', id_strategy[:locator]
  end
end