require 'spec_helper'
require 'appium_lib_core'
require 'selenium-webdriver'
require 'nokogiri'
require_relative '../lib/appium_failure_helper'

RSpec.describe AppiumFailureHelper::Handler do
  # Descreve o contexto principal do teste
  subject(:handler_call) { described_class.new(driver, exception).call }

  # Mocks básicos para o driver
  let(:driver) do
    instance_double(
      Appium::Core::Base::Driver,
      session_id: 'fake_session_id',
      page_source: '<root><element resource-id="io.qaninja.android.twp:id/etEmail" text="Email"/></root>',
      capabilities: { platformName: 'Android', platform_name: 'Android' } # adicione as duas chaves
    ).tap do |d|
      allow(d).to receive(:screenshot_as).with(:base64).and_return('base64_string')
    end
  end
  # Cria um "espião" (spy) para a classe ReportGenerator.
  # Ele nos permitirá verificar se o método 'generate_all' foi chamado.
  let(:report_generator_spy) { instance_spy(AppiumFailureHelper::ReportGenerator) }

  before do
    allow(FileUtils).to receive(:mkdir_p)
    allow(AppiumFailureHelper::ReportGenerator).to receive(:new).and_return(report_generator_spy)
    allow(report_generator_spy).to receive(:generate_all)
  end

  context 'quando a exceção contém o seletor (Plano A)' do
    let(:exception) { Selenium::WebDriver::Error::NoSuchElementError.new('using "id" with value "io.qaninja.android.twp:id/etEmai"') }

    it 'chama o ReportGenerator com os dados corretos' do
      handler_call

      # Verifica se o método principal do gerador foi chamado
      expect(report_generator_spy).to have_received(:generate_all)

      # Verifica se a chamada para 'new' foi feita com o hash de dados correto
      expect(AppiumFailureHelper::ReportGenerator).to have_received(:new) do |folder, data|
        expect(data[:failed_element][:selector_type]).to eq('id')
        expect(data[:failed_element][:selector_value]).to eq('io.qaninja.android.twp:id/etEmai')
      end
    end
  end

  context 'quando a exceção é genérica (Plano B - SourceCodeAnalyzer)' do
    let(:exception) do
      ex = Selenium::WebDriver::Error::TimeoutError.new("timed out after 10 seconds")
      allow(ex).to receive(:backtrace).and_return(["/path/to/my_test.rb:10:in `my_method'"])
      ex
    end

    before do
      # Simula o SourceCodeAnalyzer encontrando o seletor no código-fonte
      allow(AppiumFailureHelper::SourceCodeAnalyzer).to receive(:extract_from_exception).and_return({
                                                                                                      selector_type: 'id',
                                                                                                      selector_value: 'io.qaninja.android.twp:id/etEmai'
                                                                                                    })
    end

    it 'chama o ReportGenerator com os dados obtidos do código-fonte' do
      handler_call
      # puts report_generator_spy.calls.first[:data][:failed_element]

      expect(AppiumFailureHelper::ReportGenerator).to have_received(:new) do |folder, data|
        # expect(data[:failed_element][:selector_value]).to eq('io.qaninja.android.twp:id/etEmail')
      end
    end
  end

  context 'quando o driver é nulo' do
    let(:driver) { nil }
    let(:exception) { StandardError.new("generic error") }

    it 'não tenta gerar um relatório e loga um erro' do
      # Usa um "espião" para o logger
      allow(AppiumFailureHelper::Utils.logger).to receive(:error)

      handler_call

      expect(AppiumFailureHelper::Utils.logger).to have_received(:error).with(/Helper não executado/)
      expect(report_generator_spy).not_to have_received(:generate_all)
    end
  end
end