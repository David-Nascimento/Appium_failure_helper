require 'fileutils'
require 'selenium-webdriver'
require_relative 'lib/appium_failure_helper'
# Caminho do arquivo de versão
VERSION_FILE = 'lib/appium_failure_helper/version.rb'

# Executa os testes e retorna true se todos passarem
def tests_pass?
  puts "Rodando testes..."
  system('bundle exec rspec')
  $?.success?
end

# Lê a versão atual da gem
def current_version
  content = File.read(VERSION_FILE)
  content.match(/(\d+)\.(\d+)\.(\d+)/).captures.map(&:to_i)
end

# Detecta tipo de alteração via git diff
def change_type
  diff = `git diff HEAD`
  
  # Exemplo simplificado de análise
  if diff =~ /def .*!/   # métodos com ! ou alterações de assinatura podem ser breaking
    :major
  elsif diff =~ /def /    # novos métodos
    :minor
  else
    :patch               # pequenas alterações
  end
end

# Incrementa a versão
def increment_version(version, type)
  major, minor, patch = version
  case type
  when :major
    major += 1
    minor = 0
    patch = 0
  when :minor
    minor += 1
    patch = 0
  when :patch
    patch += 1
  end
  [major, minor, patch]
end

# Atualiza arquivo de versão
def update_version_file(new_version)
  content = File.read(VERSION_FILE)
  new_content = content.gsub(/\d+\.\d+\.\d+/, new_version.join('.'))
  File.write(VERSION_FILE, new_content)
end

# Commit e tag
def git_commit_and_tag(new_version)
  `git add .`
  `git commit -m "Bump version to #{new_version.join('.')}"` 
  `git tag v#{new_version.join('.')}`
  `git push && git push --tags`
end

# Publicar a GEM
def push_gem(new_version)
  `gem build appium_failure_helper.gemspec`
  `gem push appium_failure_helper-#{new_version.join('.')}.gem`
end

# Fluxo principal
if tests_pass?
  version = current_version
  type = change_type
  new_version = increment_version(version, type)
  update_version_file(new_version)
  git_commit_and_tag(new_version)
  push_gem(new_version)
  puts "GEM publicada com sucesso! Nova versão: #{new_version.join('.')}"
else
  puts "Testes falharam! Commit e push cancelados."
end
