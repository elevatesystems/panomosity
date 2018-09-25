module Panomosity
  class Panorama
    attr_accessor :images, :control_points, :variable, :optimisation_variables, :logger

    def initialize(input, logger = nil)
      @input = input
      @images = Image.parse(@input)
      @variable = PanoramaVariable.parse(@input).first
      ControlPoint.parse(@input)
      @control_points = ControlPoint.calculate_distances(@images, @variable)
      @optimisation_variables = OptimisationVariable.parse(@input)

      if logger
        @logger = logger
      else
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::DEBUG
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime}][#{severity}] #{msg}\n"
        end
      end
    end
  end
end
