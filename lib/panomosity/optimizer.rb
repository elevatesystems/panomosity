require 'panomosity/utils'

module Panomosity
  class Optimizer
    include Panomosity::Utils

    attr_accessor :panorama, :images, :control_points, :optimisation_variables, :logger

    def initialize(panorama)
      @panorama = panorama
      @images = @panorama.images
      @control_points = @panorama.control_points
      @optimisation_variables = @panorama.optimisation_variables
      @logger = @panorama.logger
    end

    def run
      variables_to_optimize = optimisation_variables.map { |v| v.attributes.keys }.flatten.uniq.sort
      if variables_to_optimize == [:d, :e]
        run_position_optimizer
      elsif variables_to_optimize == [:r]
        run_roll_optimizer
      else
        logger.error 'no optimization strategy found'
      end
    end

    def run_position_optimizer
      panorama.calculate_neighborhoods(amount_ratio: 1.0)
      panorama.calculate_neighborhood_groups(name: :horizontal, pairs: panorama.horizontal_pairs)
      panorama.calculate_neighborhood_groups(name: :vertical, pairs: panorama.vertical_pairs)

      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort

      # start horizontally
      x_avg = panorama.horizontal_neighborhoods_group.first[:x_avg]

      d_map = {}
      ds.each_with_index do |d, i|
        d_map[d] = d + -x_avg * i
      end
      logger.debug "created d_map #{d_map}"

      # vertical
      y_avg = panorama.vertical_neighborhoods_group.first[:y_avg]

      e_map = {}
      es.each_with_index do |e, i|
        e_map[e] = e + -y_avg * i
      end
      logger.debug "created e_map #{e_map}"

      x_avg = panorama.vertical_neighborhoods_group.first[:x_avg]
      y_avg = panorama.horizontal_neighborhoods_group.first[:y_avg]

      de_map = {}
      d_map.each_with_index do |(dk,dv),di|
        e_map.each_with_index do |(ek,ev),ei|
          de_map["#{dk},#{ek}"] = {}
          de_map["#{dk},#{ek}"][:d] = dv + -x_avg * ei
          de_map["#{dk},#{ek}"][:e] = ev + -y_avg * di
        end
      end
      logger.debug "created de_map #{de_map}"

      logger.debug 'updating image attributes'
      images.each do |image|
        d = image.d
        e = image.e
        image.d = de_map["#{d},#{e}"][:d]
        image.e = de_map["#{d},#{e}"][:e]
      end
    end

    def run_roll_optimizer
      r = images.map(&:r).first
      logger.debug "current roll #{r}"
      panorama.calculate_neighborhoods(amount_ratio: 1.0, log: false)
      panorama.calculate_neighborhood_groups(name: :horizontal, pairs: panorama.horizontal_pairs)
      panorama.calculate_neighborhood_groups(name: :vertical, pairs: panorama.vertical_pairs)

      y_avg = panorama.horizontal_neighborhoods_group.first[:y_avg]
      x_avg = panorama.vertical_neighborhoods_group.first[:x_avg]

      previous_y_avg = y_avg
      r -= 0.01
      logger.debug "current roll #{r}"
      panorama.images.each { |i| i.r = r }
      panorama.control_points = ControlPoint.calculate_distances(panorama.images, panorama.variable)
      panorama.calculate_neighborhoods(amount_ratio: 1.0, log: false)
      panorama.calculate_neighborhood_groups(name: :horizontal, pairs: panorama.horizontal_pairs)
      panorama.calculate_neighborhood_groups(name: :vertical, pairs: panorama.vertical_pairs)

      y_avg = panorama.horizontal_neighborhoods_group.first[:y_avg]
      x_avg = panorama.vertical_neighborhoods_group.first[:x_avg]

      while y_avg.abs < previous_y_avg.abs
        r -= 0.01
        logger.debug "current roll #{r}"
        previous_y_avg = y_avg
        panorama.images.each { |i| i.r = r }
        panorama.control_points = ControlPoint.calculate_distances(panorama.images, panorama.variable)
        panorama.calculate_neighborhoods(amount_ratio: 1.0, log: false)
        panorama.calculate_neighborhood_groups(name: :horizontal, pairs: panorama.horizontal_pairs)
        panorama.calculate_neighborhood_groups(name: :vertical, pairs: panorama.vertical_pairs)

        y_avg = panorama.horizontal_neighborhoods_group.first[:y_avg]
        x_avg = panorama.vertical_neighborhoods_group.first[:x_avg]
      end

      images.each do |image|
        image.r = r
      end
    end
  end
end
