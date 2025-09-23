# frozen_string_literal: true

require_relative "lib/appium_failure_helper/version"

Gem::Specification.new do |spec|
  spec.name = "appium_failure_helper"
  spec.version = AppiumFailureHelper::VERSION
  spec.authors = ["David Nascimento"]
  spec.email = ["halison700@gmail.com"]

  spec.summary = "Helper to capture Appium failure and extract elements information from page source"
  spec.description = "Appium Failure Helper is a Ruby gem that provides utilities to capture failures during Appium test executions. It extracts and saves relevant information from the page source, including screenshots and element details, to aid in debugging and analysis."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"
  spec.homepage      = "https://github.com/David-Nascimento/Appium_failure_helper"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Adicione as dependências de tempo de execução necessárias
  spec.add_runtime_dependency "nokogiri", "~> 1.15"
  spec.add_runtime_dependency "appium_lib", "~> 10.0"

  # Dependências de desenvolvimento para testar e construir a gem
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  # Para mais informações sobre a criação de uma nova gem, consulte o guia:
  # https://bundler.io/guides/creating_gem.html
end
