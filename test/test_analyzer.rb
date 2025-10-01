require_relative 'test_helper'

class TestAnalyzer < Minitest::Test
  def test_triage_classifies_locator_issue_for_timeout
    exception = Selenium::WebDriver::Error::TimeoutError.new
    assert_equal :locator_issue, AppiumFailureHelper::Analyzer.triage_error(exception)
  end

  def test_triage_classifies_generic_issue
    exception = StandardError.new
    assert_equal :unknown_issue, AppiumFailureHelper::Analyzer.triage_error(exception)
  end

  def test_extract_failure_details_from_enriched_message
    ex = FakeException.new('using "id" with value "io.qaninja.android.twp:id/etEmail"')
    info = AppiumFailureHelper::Analyzer.extract_failure_details(ex)
    assert_equal 'id', info[:selector_type]
    assert_equal 'io.qaninja.android.twp:id/etEmail', info[:selector_value]
  end

  def test_perform_advanced_analysis_finds_best_candidate
    failed_info = { selector_type: 'id', selector_value: 'com.app:id/btnLogi' } # Typo
    
    elements_on_screen = [
      { name: "BtnLogin", attributes: { 'resource-id' => 'com.app:id/btnLogin', 'text' => 'Login' } },
      { name: "BtnCancel", attributes: { 'resource-id' => 'com.app:id/btnCancel', 'text' => 'Cancel' } }
    ]
    
    result = AppiumFailureHelper::Analyzer.find_similar_elements(failed_info, elements_on_screen)
    
    assert_not_nil result
    assert_equal 'BtnLogin', result[:name]
    assert result[:score] > 80
  end
end