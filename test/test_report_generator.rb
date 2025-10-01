require_relative 'test_helper'

class TestReportGenerator < Minitest::Test
  include TestHelpers

  def test_generate_all_creates_all_report_files
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    output_folder = "reports_failure/failure_#{timestamp}"
    FileUtils.mkdir_p(output_folder)
    
    # Cria um hash com dados de teste mínimos
    report_data = {
      failed_element: { selector_type: 'id', selector_value: 'fake_id' },
      similar_elements: [],
      de_para_analysis: nil,
      all_page_elements: [],
      screenshot_base64: 'fake_base64',
      platform: 'android',
      timestamp: timestamp
    }
    
    generator = AppiumFailureHelper::ReportGenerator.new(output_folder, "<xml/>", report_data)
    generator.generate_all

    assert File.exist?(File.join(output_folder, "page_source_#{timestamp}.xml"))
    assert File.exist?(File.join(output_folder, "report_#{timestamp}.html"))
    assert File.exist?(File.join(output_folder, "failure_analysis_#{timestamp}.yaml"))
    assert File.exist?(File.join(output_folder, "all_elements_dump_#{timestamp}.yaml"))
  end
end