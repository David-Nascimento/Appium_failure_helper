# spec/handler_spec.rb
require 'spec_helper'
require 'appium_lib'
require 'selenium-webdriver'
require 'nokogiri'
require_relative '../lib/appium_failure_helper'

RSpec.describe AppiumFailureHelper::Handler do
  let(:driver) { double('driver') }
  let(:screenshot_base64) { 'base64string' }
  let(:page_source) { '<root><element id="btn_login"/></root>' }

  before do
    allow(driver).to receive(:session_id).and_return('123')
    allow(driver).to receive(:capabilities).and_return({'platformName' => 'Android'})
    allow(driver).to receive(:screenshot_as).with(:base64).and_return(screenshot_base64)
    allow(driver).to receive(:page_source).and_return(page_source)

    allow(AppiumFailureHelper::Utils.logger).to receive(:info)
    allow(AppiumFailureHelper::Utils.logger).to receive(:error)
    allow(AppiumFailureHelper::Utils.logger).to receive(:debug)

    allow(FileUtils).to receive(:mkdir_p)

    allow(AppiumFailureHelper::ElementRepository).to receive(:load_all).and_return({
      'btn_login' => { 'tipoBusca' => 'id', 'valor' => 'btn_login' }
    })

    allow(AppiumFailureHelper::Analyzer).to receive(:triage_error).and_return(:locator_issue)
    allow(AppiumFailureHelper::Analyzer).to receive(:extract_failure_details).and_return({})
    allow(AppiumFailureHelper::Analyzer).to receive(:find_similar_elements).and_return([])
    allow(AppiumFailureHelper::Analyzer).to receive(:find_de_para_match).and_return({})
    allow(AppiumFailureHelper::CodeSearcher).to receive(:find_similar_locators).and_return([])
    allow(AppiumFailureHelper::PageAnalyzer).to receive(:new).and_return(double(analyze: []))
    allow(AppiumFailureHelper::XPathFactory).to receive(:generate_for_node).and_return(['//xpath/alternative'])
    allow_any_instance_of(AppiumFailureHelper::ReportGenerator).to receive(:generate_all)
  end

  it 'preenche report_data[:failed_element] corretamente com fallback' do
    exception = Selenium::WebDriver::Error::NoSuchElementError.new('using "id" with value "btn_login"')
    handler = described_class.new(driver, exception)
    report_data = handler.call

    expect(report_data).to be_a(Hash)
    expect(report_data[:failed_element]).to eq({ selector_type: 'id', selector_value: 'btn_login' })
    expect(report_data[:triage_result]).to eq(:locator_issue)
  end

  it 'gera relatório mesmo em TimeoutError' do
    exception = Selenium::WebDriver::Error::TimeoutError.new('No such element: {"method":"id","selector":"btn_login"}')
    handler = described_class.new(driver, exception)
    report_data = handler.call

    expect(report_data).to be_a(Hash)
    expect(report_data[:failed_element]).to eq({ selector_type: 'id', selector_value: 'btn_login' })
  end

  it 'não levanta erro de undefined local variable' do
    exception = Selenium::WebDriver::Error::NoSuchElementError.new('using "id" with value "btn_login"')
    expect { described_class.new(driver, exception).call }.not_to raise_error
  end
end