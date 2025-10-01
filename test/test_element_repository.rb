require_relative 'test_helper'

# Mock da classe de elementos para o teste
class OnboardingElementLists
  attr_reader :elements
  def initialize
    @elements = { btnNext: ['id', 'com.app:id/next'] }
  end
end

class TestElementRepository < Minitest::Test
  include TestHelpers

  def test_load_all_merges_rb_and_yaml_files
    # Cria o arquivo .rb mock
    rb_path = File.join(ELEMENTS_DIR, 'elementLists.rb')
    File.write(rb_path, "class OnboardingElementLists; attr_reader :elements; def initialize; @elements = {rb_element: ['id', 'rb_id']}; end; end")
    
    # Cria o arquivo .yaml mock
    create_yaml_file(File.join(ELEMENTS_DIR, "login.yaml"), {'yaml_element' => {'tipoBusca'=>'id','valor'=>'yaml_id'}})
    
    # Configura a GEM para usar o arquivo .rb correto
    AppiumFailureHelper.configure do |config|
      config.elements_ruby_file = 'elementLists.rb'
    end

    map = AppiumFailureHelper::ElementRepository.load_all
    
    assert_equal 2, map.size
    assert_equal 'rb_id', map['rb_element']['valor']
    assert_equal 'yaml_id', map['yaml_element']['valor']
  end
end