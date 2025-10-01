require_relative 'test_helper'

class TestPageAnalyzer < Minitest::Test
  def test_analyze_android_element
    page_source = '<hierarchy><android.widget.Button resource-id="com.app:id/login_button" content-desc="Acessar conta"/></hierarchy>'
    analyzer = AppiumFailureHelper::PageAnalyzer.new(page_source, 'android')
    suggestions = analyzer.analyze

    assert_equal 1, suggestions.size
    suggestion = suggestions.first
    
    assert_equal 'btnAcessarConta', suggestion[:name]
    assert_equal 'id', suggestion[:locators].first[:strategy]
    assert_equal 'com.app:id/login_button', suggestion[:locators].first[:locator]
  end

  def test_analyze_ios_element
    page_source = '<AppiumAUT><XCUIElementTypeButton name="login_button" label="Acessar conta"/></AppiumAUT>'
    analyzer = AppiumFailureHelper::PageAnalyzer.new(page_source, 'ios')
    suggestions = analyzer.analyze

    assert_equal 1, suggestions.size
    suggestion = suggestions.first

    assert_equal 'btnLoginButton', suggestion[:name]
    assert_equal 'name', suggestion[:locators].first[:strategy]
    assert_equal 'login_button', suggestion[:locators].first[:locator]
  end
end