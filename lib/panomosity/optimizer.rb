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
      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort

      # start horizontally
      xs = []
      es.each_with_index do |e, i_e|
        next if i_e == es.count - 1
        ds.each_with_index do |d, i_d|
          next if i_d == ds.count - 1
          image1 = images.find { |i| i.d == d && i.e == e }
          image2 = images.find { |i| i.d == ds[i_d+1] && i.e == e }
          id1, id2 = *[image1.id, image2.id].minmax
          cps = control_points.select { |cp| cp.conn_type == :horizontal && cp.n1 == id1 && cp.n2 == id2 }
          xs << cps.map(&:prx)
        end
      end

      xs.flatten!
      x_avg, x_std = *calculate_average_and_std(name: :x, values: xs, logger: logger)
      logger.debug 'filter first standard deviations'
      xs.select! { |x| (x - x_avg).abs < x_std }
      x_avg, x_std = *calculate_average_and_std(name: :x, values: xs, logger: logger)
      logger.debug 'filter second standard deviations'
      xs.select! { |x| (x - x_avg).abs < x_std }
      x_avg, _ = *calculate_average_and_std(name: :x, values: xs, logger: logger)

      d_map = {}
      ds.each_with_index do |d, i|
        if d == ds.first
          d_map[d] = d
        else
          d_map[d] = d + -x_avg * i
        end
      end
      logger.debug "created d_map #{d_map}"

      # vertical
      ys = []
      ds.each_with_index do |d, i_d|
        next if i_d == ds.count - 1
        es.each_with_index do |e, i_e|
          next if i_e == es.count - 1
          image1 = images.find { |i| i.d == d && i.e == e }
          image2 = images.find { |i| i.d == d && i.e == es[i_e+1] }
          id1, id2 = *[image1.id, image2.id].minmax
          cps = control_points.select { |cp| cp.conn_type == :vertical && cp.n1 == id1 && cp.n2 == id2 }
          ys << cps.map(&:pry)
        end
      end

      ys.flatten!
      y_avg, y_std = *calculate_average_and_std(name: :y, values: ys, logger: logger)
      logger.debug 'filter first standard deviations'
      ys.select! { |y| (y - y_avg).abs < y_std }
      y_avg, y_std = *calculate_average_and_std(name: :y, values: ys, logger: logger)
      logger.debug 'filter second standard deviations'
      ys.select! { |y| (y - y_avg).abs < y_std }
      y_avg, _ = *calculate_average_and_std(name: :y, values: ys, logger: logger)

      e_map = {}
      es.each_with_index do |e, i|
        if e == es.first
          e_map[e] = e
        else
          e_map[e] = e + -y_avg * i
        end
      end
      logger.debug "created e_map #{e_map}"

      logger.debug 'updating image attributes'
      images.each do |image|
        image.d = d_map[image.d]
        image.e = e_map[image.e]
      end
    end

    def run_roll_optimizer
      r = images.map(&:r).first
      amount = (0.2 * (images.count)).floor
      pairs = control_points.group_by { |cp| [cp.n1, cp.n2] }.sort_by { |_, cps|  [calculate_average_and_std(values: cps.map(&:prdist)).first, -cps.count] }[0..(amount-1)]
      pairs.select{|_,cps| cps.first.conn_type == :horizontal}.each do |pair, cps|
        logger.debug "#{pair} #{cps.map(&:detailed_info).join("\n")}"
      end
    end
  end
end
