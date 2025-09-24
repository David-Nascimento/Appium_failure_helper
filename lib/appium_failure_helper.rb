# frozen_string_literal: true

require 'nokogiri'
require 'fileutils'
require 'base64'
require 'yaml'
require 'logger'
require 'did_you_mean'
require 'cgi'

# Carrega todos os nossos novos módulos
require_relative 'appium_failure_helper/utils'
require_relative 'appium_failure_helper/analyzer'
require_relative 'appium_failure_helper/element_repository'
require_relative 'appium_failure_helper/page_analyzer'
require_relative 'appium_failure_helper/report_generator'
require_relative 'appium_failure_helper/handler'
module AppiumFailureHelper
  class Error < StandardError; end
  def self.handler_failure(driver, exception)
    Handler.call(driver, exception)
  end
end
