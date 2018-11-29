require 'panomosity/utils'

module Panomosity
  class Neighborhood
    include Panomosity::Utils

    attr_accessor :center, :pair, :distance, :pair_distance, :control_points, :control_points_within_std, :prdist_avg,
                  :prdist_std, :prx_avg, :prx_std, :pry_avg, :pry_std

    def initialize(center:, pair:, distance:)
      @center = center
      @pair = pair
      @distance = distance
    end

    def calculate
      # Do not include generated control points in neighborhood calculations
      pair_control_points = pair.control_points.select(&:not_generated?)

      # Instead of setting a static distance use a distance that is dependent on the type of connection
      if pair.horizontal?
        @pair_distance = (pair.first_image.h * 0.1).round
        @control_points = pair_control_points.select do |cp|
          cp.x1.between?(center.x1 - distance, center.x1 + distance) && cp.y1.between?(center.y1 - pair_distance, center.y1 + pair_distance)
        end
      else
        @pair_distance = (pair.first_image.w * 0.1).round
        @control_points = pair_control_points.select do |cp|
          cp.x1.between?(center.x1 - pair_distance, center.x1 + pair_distance) && cp.y1.between?(center.y1 - distance, center.y1 + distance)
        end
      end

      @prdist_avg, @prdist_std = *calculate_average_and_std(values: control_points.map(&:prdist), ignore_empty: true)
      @prx_avg, @prx_std = *calculate_average_and_std(values: control_points.map(&:prx), ignore_empty: true)
      @pry_avg, @pry_std = *calculate_average_and_std(values: control_points.map(&:pry), ignore_empty: true)


      if Pair.panorama.calibration? && @control_points.count == 2
        # If we are viewing calibration control points we are going to have fewer of them. Increase the standard
        # deviation so that more control points are included
        std = prdist_std * 4
        @control_points_within_std = pair_control_points.select { |c| c.prdist.between?(center.prdist - std, center.prdist + std) }
      else
        # add in control points that have similar distances (within std)
        @control_points_within_std = pair_control_points.select { |c| c.prdist.between?(center.prdist - prdist_std, center.prdist + prdist_std) }
      end

      self
    end

    def info
      "neighborhood: center: (#{center.x1},#{center.y1}) | prx_avg,prx_std: #{prx_avg},#{prx_std} | pry_avg,pry_std: #{pry_avg},#{pry_std} | prdist_avg,prdist_std: #{prdist_avg},#{prdist_std}"
    end
  end
end
