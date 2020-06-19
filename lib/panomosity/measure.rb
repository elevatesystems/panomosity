require 'panomosity/utils'

module Panomosity
  class Measure
    include Panomosity::Utils

    ATTRIBUTES = [:type, :center, :distances]
    DEFAULT_DISTANCE = 100

    attr_reader :options
    attr_accessor *ATTRIBUTES

    def initialize(attributes = {})
      @attributes = attributes
      @attributes[:center] ||= {}
      @attributes[:distances] ||= {}
    end

    def position?
      type == :position
    end

    def distance?
      type == :distance
    end

    def type
      @attributes[:type]
    end

    def center
      @attributes[:center]
    end

    def distances
      @attributes[:distances]
    end

    def update(attributes = {})

      @attributes.merge!(attributes)
    end

    def update_distances(values = {})
      @attributes[:distances].merge!(values)
    end

    def includes?(*values)
      center.values.zip(values, distances.values).all? { |center, value, distance| (center - value).abs <= distance }
    end

    def attributes
      { type: type, center: center.values, distances: distances.values }
    end
  end
end
