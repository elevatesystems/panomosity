module Panomosity
  module Binaries
    BASE_PATH = File.expand_path('../../bin', __dir__).freeze

    NONA_MASK = File.expand_path('nona-mask', BASE_PATH).freeze
    NONA = 'nona'.freeze
  end
end
