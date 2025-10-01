# test/test_helper.rb
require 'minitest/autorun'
require 'selenium-webdriver' # <-- ADICIONADO: Garante que as classes de erro do Selenium estejam disponíveis
require_relative '../lib/appium_failure_helper'

# --- Mocks (Simuladores) Compartilhados ---
class FakeException < StandardError
  attr_reader :backtrace
  def initialize(message = "Fake Error", backtrace = ["fake_file.rb:10:in `fake_method'"])
    super(message)
    @backtrace = backtrace
  end
end

class FakeDriver
  attr_reader :capabilities, :page_source
  def initialize(platform: 'android', page_source: '')
    @capabilities = { platformName: platform }
    @page_source = page_source
  end
  def session_id; 'fake_session_id'; end
  def screenshot_as(format); 'fake_base64_string'; end
end

# --- Módulo de Helpers para os Testes ---
module TestHelpers
  ELEMENTS_DIR = 'features/elements'
  REPORTS_DIR = 'reports_failure'

  def setup
    FileUtils.rm_rf(REPORTS_DIR)
    FileUtils.rm_rf('features')
    FileUtils.mkdir_p(File.join(ELEMENTS_DIR, 'subfolder'))
  end

  def teardown
    FileUtils.rm_rf(REPORTS_DIR)
    FileUtils.rm_rf('features')
  end

  def create_yaml_file(path, content)
    File.write(path, YAML.dump(content))
  end
end