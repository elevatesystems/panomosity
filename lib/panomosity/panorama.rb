module Panomosity
  class Panorama
    include Panomosity::Utils

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

    def calculate_neighborhoods(distance: 30, amount_ratio: 0.2)
      pairs = control_points.group_by { |cp| [cp.n1, cp.n2] }
      amount = (amount_ratio * (images.count)).floor

      # separate out into horizontal and vertical pairs
      horizontal_pairs = pairs.select { |_,cps| cps.first.conn_type == :horizontal }
      vertical_pairs = pairs.select { |_,cps| cps.first.conn_type == :vertical }

      # sort pairs by average distance first and number of control points descending second
      horizontal_pairs = horizontal_pairs.sort_by { |_, cps|  [calculate_average_and_std(values: cps.map(&:prdist)).first, -cps.count] }
      vertical_pairs = vertical_pairs.sort_by { |_, cps|  [calculate_average_and_std(values: cps.map(&:prdist)).first, -cps.count] }

      # select a set amount
      horizontal_pairs = horizontal_pairs[0..(amount-1)]
      vertical_pairs = vertical_pairs[0..(amount-1)]

      # looks for the highest concentration of points with similar distances within the neighborhood (30px) of the average
      # group cps that are close in distance to each other
      # start with horizontal pairs
      @horizontal_pairs = calculate_neighborhood_info(pairs: horizontal_pairs, distance: distance)
      log_detailed_neighborhood_info(name: :horizontal, pairs: @horizontal_pairs)

      # vertical pairs
      @vertical_pairs = calculate_neighborhood_info(pairs: vertical_pairs, distance: distance)
      log_detailed_neighborhood_info(name: :vertical, pairs: @vertical_pairs)

      { horizontal_pairs: @horizontal_pairs, vertical_pairs: @vertical_pairs }
    end

    def calculate_neighborhood_info(pairs: [], distance: 30)
      pairs.map do |pair, cps|
        neighborhoods = cps.map do |cp|
          neighborhood = cps.select { |c| c.x1.between?(cp.x1 - distance, cp.x1 + distance) && c.y1.between?(cp.y1 - distance, cp.y1 + distance) }
          if neighborhood.count > 1
            prdist_avg, prdist_std = *calculate_average_and_std(values: neighborhood.map(&:prdist))
            prx_avg, prx_std = *calculate_average_and_std(values: neighborhood.map(&:prx))
            pry_avg, pry_std = *calculate_average_and_std(values: neighborhood.map(&:pry))

            # add in control points that have similar distances (within std)
            neighborhood_within_std = cps.select { |c| c.prdist.between?(cp.prdist - prdist_std, cp.prdist + prdist_std) }
            {
              cp: cp,
              prdist_avg: prdist_avg,
              prdist_std: prdist_std,
              prx_avg: prx_avg,
              prx_std: prx_std,
              pry_avg: pry_avg,
              pry_std: pry_std,
              neighborhood: neighborhood,
              neighborhood_within_std: neighborhood_within_std
            }
          else
            nil
          end
        end.compact
        # gets all control points for neighborhoods with a good std of distance
        control_points_within_a_std = neighborhoods.select { |n| n[:neighborhood_within_std].count >= 3 }.flatten

        best_neighborhood = neighborhoods.sort_by { |n| -n[:neighborhood].count }.first
        {
          pair: pair,
          control_points: cps,
          neighborhoods: neighborhoods,
          best_neighborhood: best_neighborhood,
          control_points_within_a_std: control_points_within_a_std
        }
      end
    end

    def log_detailed_neighborhood_info(name: :horizontal, pairs: [])
      pair = pairs.sort_by{|pair| -pair[:best_neighborhood][:neighborhood].count}.first
      pairs.each do |p|
        logger.debug "#{name} pair #{p[:pair]} found #{p[:best_neighborhood][:neighborhood].count} control points"
        p[:neighborhoods].each do |neighborhood|
          logger.debug "neighborhood centered at #{neighborhood[:cp].x1},#{neighborhood[:cp].y1}: #{neighborhood[:neighborhood].count} control points"
          logger.debug "neighborhood centered at #{neighborhood[:cp].x1},#{neighborhood[:cp].y1}: prdist #{neighborhood[:prdist_avg]},#{neighborhood[:prdist_std]} prx #{neighborhood[:prx_avg]},#{neighborhood[:prx_std]} pry #{neighborhood[:pry_avg]},#{neighborhood[:pry_std]}"
          neighborhood[:neighborhood].each do |point|
            logger.debug point.detailed_info
          end
        end
      end
      pairs.each do |p|
        logger.debug "#{name} pair #{p[:pair]} found #{p[:best_neighborhood][:neighborhood].count} control points"
      end
      logger.debug "#{name} pair #{pair[:pair]} found #{pair[:best_neighborhood][:neighborhood].count} control points"
    end

    def clean_control_points(options = {})
      bad_control_points = []
      min_control_points = 5
      control_points.group_by { |cp| [cp.n1, cp.n2] }.select { |_, cps| cps.count > min_control_points }.each do |pair, cps|
        logger.debug "cleaning pair #{pair.first} <> #{pair.last}"
        average_x, x_std = *calculate_average_and_std(name: :x, values: cps.map(&:px), logger: logger)
        average_y, y_std = *calculate_average_and_std(name: :y, values: cps.map(&:py), logger: logger)

        max_removal = ((options[:max_removal] || 0.2) * cps.count).floor
        min_cps = 8
        max_iterations = 10
        iterations = 0
        bad_cps = cps.select { |cp| (cp.px - average_x).abs >= x_std || (cp.py - average_y).abs >= y_std }
        while bad_cps.count > max_removal && (cps.count - bad_cps.count) >= min_cps && iterations <= max_iterations
          x_std *= 1.1
          y_std *= 1.1
          iterations += 1
          bad_cps = cps.select { |cp| (cp.px - average_x).abs >= x_std || (cp.py - average_y).abs >= y_std }
        end

        logger.info "found #{bad_cps.count} outliers"
        bad_control_points << bad_cps if bad_cps.count <= max_removal
      end
      bad_control_points.flatten!
    end

    def clean_control_points_neighborhoods(options = {})
      calculate_neighborhoods(amount_ratio: 1.0)
      control_points = (@horizontal_pairs.map { |pair| pair[:control_points_within_a_std].map { |n| n[:neighborhood_within_std] } } +
                        @vertical_pairs.map { |pair| pair[:control_points_within_a_std].map { |n| n[:neighborhood_within_std] } }).flatten.uniq { |cp| cp.raw }
      bad_control_points = @control_points.reject { |cp| control_points.map(&:raw).include?(cp.raw) }
    end


  end
end
