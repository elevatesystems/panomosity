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

    def run_position_optimizer(xh_avg: nil, yh_avg: nil, xv_avg: nil, yv_avg: nil)
      if xh_avg || yh_avg || xv_avg || yv_avg
        logger.info "applying custom values of xh_avg: #{xh_avg}, yh_avg: #{yh_avg}, xv_avg: #{xv_avg}, yv_avg: #{yv_avg}"
      end

      Pair.calculate_neighborhoods(panorama)
      Pair.calculate_neighborhood_groups

      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort

      # get the average error for the best neighborhood group
      x_avg = xh_avg || NeighborhoodGroup.horizontal.first.x_avg
      y_avg = yv_avg || NeighborhoodGroup.vertical.first.y_avg

      # start horizontally
      d_map = {}
      ds.each_with_index do |d, i|
        d_map[d] = d + -x_avg * i
      end
      logger.debug "created d_map #{d_map}"

      # vertical
      e_map = {}
      es.each_with_index do |e, i|
        e_map[e] = e + -y_avg * i
      end
      logger.debug "created e_map #{e_map}"

      # add in the other offset
      x_avg = xv_avg || NeighborhoodGroup.vertical.first.x_avg
      y_avg = yh_avg || NeighborhoodGroup.horizontal.first.y_avg

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

    def run_roll_optimizer(apply_roll: nil)
      r = images.map(&:r).first
      original_roll = r
      logger.debug "current roll #{r}"

      if apply_roll
        logger.info "apply rolling custom roll #{apply_roll}"
        images.each do |image|
          image.r = apply_roll
        end
        return
      end

      # we grab the top 5 neighborhood groups and get the average distance for them and average that
      dist_avg = calculate_average_distance

      r -= 0.01
      logger.debug "current roll #{r}"
      new_dist_avg = recalculate_average_distance(roll: r)
      logger.debug "avg: #{dist_avg} new_avg: #{new_dist_avg}"

      operation_map = { :- => 'subtracting', :+ => 'adding' }
      if new_dist_avg < dist_avg
        operation = :-
        logger.debug "found that #{operation_map[operation]} roll will decrease distances, resetting roll..."
      else
        operation = :+
        logger.debug "found that #{operation_map[operation]} roll will decrease distances, resetting roll..."
        r = original_roll
        r += 0.01
        logger.debug "current roll #{r}"
        new_dist_avg = recalculate_average_distance(roll: r)
      end

      logger.debug "avg: #{dist_avg} new_avg: #{new_dist_avg}"
      if new_dist_avg > dist_avg
        logger.debug "found that #{operation_map[operation]} roll will also increase distances, leaving roll unchanged "
        r = original_roll
      end

      while new_dist_avg <= dist_avg
        r = r.send(operation, 0.01)
        logger.debug "current roll #{r}"
        dist_avg = new_dist_avg
        new_dist_avg = recalculate_average_distance(roll: r)
        logger.debug "avg: #{dist_avg} new_avg: #{new_dist_avg}"
      end

      images.each do |image|
        image.r = r
      end
    end

    def calculate_average_distance
      Pair.calculate_neighborhoods(panorama)
      Pair.calculate_neighborhood_groups
      horizontal_distances = NeighborhoodGroup.horizontal[0..4].map(&:prdist_avg)
      vertical_distances = NeighborhoodGroup.vertical[0..4].map(&:prdist_avg)
      calculate_average(values: horizontal_distances + vertical_distances)
    end

    def recalculate_average_distance(roll:)
      panorama.images.each { |i| i.r = roll }
      panorama.control_points = ControlPoint.calculate_distances(panorama.images, panorama.variable)
      calculate_average_distance
    end
  end
end
