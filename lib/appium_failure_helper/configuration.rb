module AppiumFailureHelper
  class Configuration
    # Define as opções que o usuário poderá configurar
    attr_accessor :elements_path, :elements_ruby_file

    def initialize
      # Define os valores PADRÃO.
      # Se o usuário não configurar nada, a GEM usará estes valores.
      @elements_path = 'features/elements'
      @elements_ruby_file = 'elementLists.rb'
    end
  end
end