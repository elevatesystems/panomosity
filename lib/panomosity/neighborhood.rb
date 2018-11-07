require 'panomosity/utils'

module Panomosity
  class Neighborhood
    include Panomosity::Utils

    attr_accessor :center, :pair, :distance, :control_points, :control_points_within_std, :prdist_avg, :prdist_std,
                  :prx_avg, :prx_std, :pry_avg, :pry_std

    def initialize(center:, pair:, distance:)
      @center = center
      @pair = pair
      @distance = distance
    end

    def calculate
      @control_points = pair.control_points.select do |cp|
        cp.x1.between?(center.x1 - distance, center.x1 + distance) && cp.y1.between?(center.y1 - distance, center.y1 + distance)
      end

      @prdist_avg, @prdist_std = *calculate_average_and_std(values: control_points.map(&:prdist))
      @prx_avg, @prx_std = *calculate_average_and_std(values: control_points.map(&:prx))
      @pry_avg, @pry_std = *calculate_average_and_std(values: control_points.map(&:pry))

      # add in control points that have similar distances (within std)
      @control_points_within_std = pair.control_points.select { |c| c.prdist.between?(center.prdist - prdist_std, center.prdist + prdist_std) }
      self
    end

    def info
      "neighborhood: center: (#{center.x1},#{center.y1}) | prx_avg,prx_std: #{prx_avg},#{prx_std} | pry_avg,pry_std: #{pry_avg},#{pry_std} | prdist_avg,prdist_std: #{prdist_avg},#{prdist_std}"
    end
  end
end
