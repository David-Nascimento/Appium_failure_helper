# spec/appium_failure_helper/handler_spec.rb
require 'spec_helper'
require 'fileutils'
require 'selenium-webdriver'
require_relative '../lib/appium_failure_helper'

RSpec.describe AppiumFailureHelper::Handler do
  let(:driver) do
    instance_double("Appium::Core::Base::Driver",
                    session_id: "fake_session",
                    capabilities: { 'platformName' => 'Android' },
                    screenshot_as: "fake_screenshot",
                    page_source: "<xml></xml>")
  end
  let(:exception) { Selenium::WebDriver::Error::NoSuchElementError.new('element not found') }
  let(:timestamp) { Time.now.strftime('%Y%m%d_%H%M%S') }
  let(:output_folder) { "reports_failure/failure_#{timestamp}" }
  let(:captured_report_data) { {} }
   
  before do
    allow(driver).to receive(:session_id).and_return('12345')
    allow(driver).to receive(:capabilities).and_return({ 'platformName' => 'Android' })
    allow(driver).to receive(:screenshot_as).with(:base64).and_return('screenshot_base64')
    allow(driver).to receive(:page_source).and_return('<xml><element id="1"/></xml>')
    allow(FileUtils).to receive(:mkdir_p)
    allow(AppiumFailureHelper::Analyzer).to receive(:triage_error).and_return(:locator_issue)
    allow(AppiumFailureHelper::Analyzer).to receive(:extract_failure_details).and_return({ selector_type: 'id', selector_value: 'btn_login' })
    allow(AppiumFailureHelper::SourceCodeAnalyzer).to receive(:extract_from_exception).and_return({})
    allow(AppiumFailureHelper::PageAnalyzer).to receive(:new).and_return(double(analyze: []))
    allow(AppiumFailureHelper::ElementRepository).to receive(:load_all).and_return([])
    allow(AppiumFailureHelper::Analyzer).to receive(:find_similar_elements).and_return([])
    allow(AppiumFailureHelper::Analyzer).to receive(:find_de_para_match).and_return([])
    allow(AppiumFailureHelper::CodeSearcher).to receive(:find_similar_locators).and_return([])
    allow(AppiumFailureHelper::Utils).to receive_message_chain(:logger, :info)
    allow_any_instance_of(AppiumFailureHelper::ReportGenerator).to receive(:generate_all)
    allow(AppiumFailureHelper::ReportGenerator).to receive(:new) do |folder, report_data|
      captured_report_data.replace(report_data) # armazena o report_data real
      instance_double("ReportGenerator", generate_all: true)
    end
  end

  it "preenche report_data[:failed_element] corretamente" do
    handler = described_class.new(driver, exception)
    handler.call

    expect(captured_report_data).to be_a(Hash)
    expect(captured_report_data[:failed_element]).to include(:selector_type, :selector_value)

  end


  it 'gera relatório analítico mesmo em NoSuchElementError' do
    handler = described_class.new(driver, Selenium::WebDriver::Error::NoSuchElementError.new('not found'))
    expect { handler.call }.not_to raise_error
  end

  it 'não levanta erro de undefined local variable' do
    handler = described_class.new(driver, exception)
    expect { handler.call }.not_to raise_error
  end
end
