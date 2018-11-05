module Panomosity
  class Panorama
    include Panomosity::Utils

    attr_accessor :images, :control_points, :variable, :optimisation_variables, :logger, :horizontal_pairs,
                  :vertical_pairs, :horizontal_neighborhoods_group, :vertical_neighborhoods_group

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

    def calculate_neighborhoods(distance: 30, amount_ratio: 0.2, log: true)
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
      log_detailed_neighborhood_info(name: :horizontal, pairs: @horizontal_pairs) if log

      # vertical pairs
      @vertical_pairs = calculate_neighborhood_info(pairs: vertical_pairs, distance: distance)
      log_detailed_neighborhood_info(name: :vertical, pairs: @vertical_pairs) if log

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

    # get all neighborhoods based on how many control points are within the std of the distance
    def calculate_neighborhood_groups(name: :horizontal, pairs: [])
      neighborhood_default = 3
      total_neighborhoods = pairs.map { |p| p[:neighborhoods].select { |n| n[:neighborhood_within_std].count >= neighborhood_default }}.flatten

      if total_neighborhoods.map { |n| n[:prdist_std] }.empty?
        logger.warn 'total_neighborhoods came up empty, neighborhood default count to 2'
        neighborhood_default = 2
        total_neighborhoods = pairs.map { |p| p[:neighborhoods].select { |n| n[:neighborhood_within_std].count >= neighborhood_default }}.flatten
        raise 'still could not find neighborhoods' if total_neighborhoods.map { |n| n[:prdist_std] }.empty?
      end

      logger.debug "twice reducing #{name} neighborhood std outliers"
      avg, std = *calculate_average_and_std(values: total_neighborhoods.map { |n| n[:prdist_std] })
      total_neighborhoods.select! { |n| (avg - n[:prdist_std]).abs <= std }
      avg, std = *calculate_average_and_std(values: total_neighborhoods.map { |n| n[:prdist_std] })
      total_neighborhoods.select! { |n| (avg - n[:prdist_std]).abs <= std }
      neighborhood_group = total_neighborhoods.map do |neighborhood|
        ns_total = total_neighborhoods.select { |n| (n[:prdist_avg] - neighborhood[:prdist_avg]).abs < neighborhood[:prdist_std] }
        cps_total = ns_total.map { |n| n[:neighborhood_within_std].count }.reduce(:+)
        x_avg, _ = *calculate_average_and_std(values: ns_total.map { |n| n[:neighborhood_within_std] }.flatten.map(&:px))
        y_avg, _ = *calculate_average_and_std(values: ns_total.map { |n| n[:neighborhood_within_std] }.flatten.map(&:py))
        {
          neighborhood: neighborhood,
          total_neighboorhoods: ns_total,
          total_control_points: cps_total,
          prdist_avg: neighborhood[:prdist_avg],
          prdist_std: neighborhood[:prdist_std],
          x_avg: x_avg,
          y_avg: y_avg
        }
      end
      neighborhood_group.sort_by { |n| -n[:total_control_points] }[0..5].each do |ng|
        logger.debug "#{ng[:prdist_avg]} #{ng[:prdist_std]} #{ng[:total_control_points]} x#{ng[:x_avg]} y#{ng[:y_avg]}"
      end

      if name == :horizontal
        @horizontal_neighborhoods_group = neighborhood_group.sort_by { |n| -n[:total_control_points] }
      else
        @vertical_neighborhoods_group = neighborhood_group.sort_by { |n| -n[:total_control_points] }
      end
    end

    def log_detailed_neighborhood_info(name: :horizontal, pairs: [])
      logger.debug "showing #{name} pair information"
      pair = pairs.sort_by{|pair| pair[:best_neighborhood] ? -pair[:best_neighborhood][:neighborhood].count : 0}.first
      pairs.each do |p|
        logger.debug "#{name} pair #{p[:pair]} found #{p[:best_neighborhood] ? p[:best_neighborhood][:neighborhood].count : 0} control points"
        p[:neighborhoods].each do |neighborhood|
          logger.debug "neighborhood centered at #{neighborhood[:cp].x1},#{neighborhood[:cp].y1}: #{neighborhood[:neighborhood].count} control points"
          logger.debug "neighborhood centered at #{neighborhood[:cp].x1},#{neighborhood[:cp].y1}: prdist #{neighborhood[:prdist_avg]},#{neighborhood[:prdist_std]} prx #{neighborhood[:prx_avg]},#{neighborhood[:prx_std]} pry #{neighborhood[:pry_avg]},#{neighborhood[:pry_std]}"
          neighborhood[:neighborhood].each do |point|
            logger.debug point.detailed_info
          end
        end
      end
      pairs.each do |p|
        logger.debug "#{name} pair #{p[:pair]} found #{p[:best_neighborhood] ? p[:best_neighborhood][:neighborhood].count : 0} control points"
      end
      #logger.debug "#{name} pair #{pair[:pair]} found #{pair[:best_neighborhood] ? pair[:best_neighborhood][:neighborhood].count : 0} control points"
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

    def fix_unconnected_image_pairs
      horizontal_control_points, vertical_control_points = *control_points.partition { |cp| cp.conn_type == :horizontal }
      control_points_of_pair = horizontal_control_points.group_by { |cp| [cp.n1, cp.n2] }.sort_by { |_, members| members.count }.last.last
      logger.debug "found horizontal pair #{control_points_of_pair.first.n1} <> #{control_points_of_pair.first.n2} with #{control_points_of_pair.count} connections"
      average_distance, distance_std = *calculate_average_and_std(name: :distance, values: control_points_of_pair.map(&:pdist), logger: logger)
      horizontal_control_points_of_pair = control_points_of_pair.select { |cp| (cp.pdist - average_distance).abs < distance_std }
      logger.info "removed #{control_points_of_pair.count - horizontal_control_points_of_pair.count} outliers"
      # For logging
      calculate_average_and_std(name: :distance, values: horizontal_control_points_of_pair.map(&:pdist), logger: logger)

      control_points_of_pair = vertical_control_points.group_by { |cp| [cp.n1, cp.n2] }.sort_by { |_, members| members.count }.last.last
      logger.debug "found vertical pair #{control_points_of_pair.first.n1} <> #{control_points_of_pair.first.n2} with #{control_points_of_pair.count} connections"
      average_distance, distance_std = *calculate_average_and_std(name: :distance, values: control_points_of_pair.map(&:pdist), logger: logger)
      vertical_control_points_of_pair = control_points_of_pair.select { |cp| (cp.pdist - average_distance).abs < distance_std }
      logger.info "removed #{control_points_of_pair.count - vertical_control_points_of_pair.count} outliers"
      # For logging
      calculate_average_and_std(name: :distance, values: vertical_control_points_of_pair.map(&:pdist), logger: logger)

      logger.info 'finding unconnected image pairs'
      unconnected_image_pairs = find_unconnected_image_pairs

      logger.info unconnected_image_pairs.map { |i| { type: i[:type], pair: i[:pair].map(&:id) } }

      logger.info 'finding control points with unrealistic distances (<1)'
      bad_control_points = control_points.select { |cp| cp.pdist <= 1.0 }
      logger.info 'adding pairs that have do not have enough control points (<3)'
      changing_control_points_pairs = control_points.group_by { |cp| [cp.n1, cp.n2] }.select { |_, cps| cps.count < 3 }
      changed_pairs = []

      logger.info 'writing new control points'
      control_point_lines_started = false
      @lines = @input.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp.nil?
          # Control point lines ended
          if control_point_lines_started
            control_point_lines_started = false
            unconnected_image_pairs.map do |pair|
              if pair[:type] == :horizontal
                control_point = horizontal_control_points_of_pair.first
              else
                control_point = vertical_control_points_of_pair.first
              end

              x_diff = control_point.x2 - control_point.x1
              y_diff = control_point.y2 - control_point.y1

              x1 = x_diff <= 0 ? -x_diff + 15 : 0
              y1 = y_diff <= 0 ? -y_diff + 15 : 0

              control_point[:n] = pair[:pair].first.id
              control_point[:N] = pair[:pair].last.id
              control_point[:x] = x1
              control_point[:X] = x1 + x_diff
              control_point[:y] = y1
              control_point[:Y] = y1 + y_diff

              logger.debug "adding control points connecting #{control_point.n1} <> #{control_point.n2}"
              i = images.first
              3.times.map do
                if control_point.conn_type == :horizontal
                  control_point[:x] += 5
                  control_point[:X] += 5
                  control_point[:y] += i.h * 0.25
                  control_point[:Y] += i.h * 0.25
                else
                  control_point[:x] += i.w * 0.25
                  control_point[:X] += i.w * 0.25
                  control_point[:y] += 5
                  control_point[:Y] += 5
                end
                control_point.to_s
              end.join
            end + [line]
          else
            next line
          end
        else
          control_point_lines_started = true
          bad_control_point = bad_control_points.find { |cp| cp.raw == line }
          changing_control_point_pair = changing_control_points_pairs.find { |_, cps| cps.find { |cp| cp.raw == line } }

          if bad_control_point
            if bad_control_point.conn_type == :horizontal
              control_point = horizontal_control_points_of_pair.first
            else
              control_point = vertical_control_points_of_pair.first
            end

            x_diff = control_point.x2 - control_point.x1
            y_diff = control_point.y2 - control_point.y1

            x1 = x_diff <= 0 ? -x_diff + 15 : 0
            y1 = y_diff <= 0 ? -y_diff + 15 : 0

            control_point[:n] = bad_control_point[:n]
            control_point[:N] = bad_control_point[:N]
            control_point[:x] = x1
            control_point[:X] = x1 + x_diff
            control_point[:y] = y1
            control_point[:Y] = y1 + y_diff

            logger.debug "replacing unrealistic control point connecting #{control_point.n1} <> #{control_point.n2}"
            i = images.first
            3.times.map do
              if control_point.conn_type == :horizontal
                control_point[:x] += 5
                control_point[:X] += 5
                control_point[:y] += i.h * 0.25
                control_point[:Y] += i.h * 0.25
              else
                control_point[:x] += i.w * 0.25
                control_point[:X] += i.w * 0.25
                control_point[:y] += 5
                control_point[:Y] += 5
              end
              control_point.to_s
            end.join
          elsif changing_control_point_pair && !changed_pairs.include?(changing_control_point_pair.first)
            changed_pairs << changing_control_point_pair.first
            bad_control_point = changing_control_point_pair.last.first
            if bad_control_point.conn_type == :horizontal
              control_point = horizontal_control_points_of_pair.first
            else
              control_point = vertical_control_points_of_pair.first
            end

            x_diff = control_point.x2 - control_point.x1
            y_diff = control_point.y2 - control_point.y1

            x1 = x_diff <= 0 ? -x_diff + 15 : 0
            y1 = y_diff <= 0 ? -y_diff + 15 : 0

            control_point[:n] = bad_control_point[:n]
            control_point[:N] = bad_control_point[:N]
            control_point[:x] = x1
            control_point[:X] = x1 + x_diff
            control_point[:y] = y1
            control_point[:Y] = y1 + y_diff

            logger.debug "adding control points connecting #{control_point.n1} <> #{control_point.n2}"
            i = images.first
            3.times.map do
              if control_point.conn_type == :horizontal
                control_point[:x] += 5
                control_point[:X] += 5
                control_point[:y] += i.h * 0.25
                control_point[:Y] += i.h * 0.25
              else
                control_point[:x] += i.w * 0.25
                control_point[:X] += i.w * 0.25
                control_point[:y] += 5
                control_point[:Y] += 5
              end
              control_point.to_s
            end.join
          else
            next line
          end
        end
      end.compact.flatten
    end

    def fix_unconnected_image_pairs_neighborhoods
      calculate_neighborhoods(amount_ratio: 1.0)
      calculate_neighborhood_groups(name: :horizontal, pairs: @horizontal_pairs)
      calculate_neighborhood_groups(name: :vertical, pairs: @vertical_pairs)

      logger.info 'finding unconnected image pairs'
      unconnected_image_pairs = find_unconnected_image_pairs
      logger.info unconnected_image_pairs.map { |i| { type: i[:type], pair: i[:pair].map(&:id) } }

      logger.info 'finding control points with unrealistic distances (<1)'
      bad_control_points = control_points.select { |cp| cp.pdist <= 1.0 }
      logger.info 'adding pairs that have do not have enough control points (<3)'
      changing_control_points_pairs = control_points.group_by { |cp| [cp.n1, cp.n2] }.select { |_, cps| cps.count < 3 }
      changed_pairs = []

      logger.info 'writing new control points'
      control_point_lines_started = false
      @lines = @input.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp.nil?
          # Control point lines ended
          if control_point_lines_started
            control_point_lines_started = false
            unconnected_image_pairs.map do |pair|
              generate_control_points(pair: pair, message: 'adding control points connecting')
            end + [line]
          else
            next line
          end
        else
          control_point_lines_started = true
          bad_control_point = bad_control_points.find { |cp| cp.raw == line }
          changing_control_point_pair = changing_control_points_pairs.find { |_, cps| cps.find { |cp| cp.raw == line } }

          if bad_control_point
            generate_control_points(bad_control_point: bad_control_point, message: 'replacing unrealistic control point connecting')
          elsif changing_control_point_pair && !changed_pairs.include?(changing_control_point_pair.first)
            changed_pairs << changing_control_point_pair.first
            bad_control_point = changing_control_point_pair.last.first
            generate_control_points(bad_control_point: bad_control_point, message: 'adding control points connecting')
          else
            next line
          end
        end
      end.compact.flatten
    end

    def find_unconnected_image_pairs
      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort

      unconnected_image_pairs = []
      # horizontal connection checking
      es.each do |e|
        ds.each_with_index do |d, index|
          next if index == (ds.count - 1)
          image_1 = images.find { |i| i.e == e && i.d == d }
          image_2 = images.find { |i| i.e == e && i.d == ds[index+1] }
          connected = control_points.any? { |cp| (cp.n1 == image_1.id && cp.n2 == image_2.id) || (cp.n1 == image_2.id && cp.n2 == image_1.id) }
          unconnected_image_pairs <<  { type: :horizontal, pair: [image_1, image_2].sort_by(&:id) } unless connected
        end
      end

      # vertical connection checking
      ds.each do |d|
        es.each_with_index do |e, index|
          next if index == (es.count - 1)
          image_1 = images.find { |i| i.d == d && i.e == e }
          image_2 = images.find { |i| i.d == d && i.e == es[index+1] }
          connected = control_points.any? { |cp| (cp.n1 == image_1.id && cp.n2 == image_2.id) || (cp.n1 == image_2.id && cp.n2 == image_1.id) }
          unconnected_image_pairs << { type: :vertical, pair: [image_1, image_2].sort_by(&:id) } unless connected
        end
      end

      unconnected_image_pairs
    end

    def generate_control_points(pair: nil, bad_control_point: nil, message: '')
      if pair
        if pair[:type] == :horizontal
          group = @horizontal_neighborhoods_group.first
        else
          group = @vertical_neighborhoods_group.first
        end
      else
        if bad_control_point.conn_type == :horizontal
          group = @horizontal_neighborhoods_group.first
        else
          group = @vertical_neighborhoods_group.first
        end
      end

      control_point = ControlPoint.new(group[:neighborhood][:cp].attributes)

      if pair
        control_point[:n] = pair[:pair].first.id
        control_point[:N] = pair[:pair].last.id
      else
        control_point[:n] = bad_control_point[:n]
        control_point[:N] = bad_control_point[:N]
      end

      image_1 = images.find { |i| i.id == control_point[:n] }
      image_2 = images.find { |i| i.id == control_point[:N] }

      x_diff = group[:x_avg] + (image_2.d - image_1.d)
      y_diff = group[:y_avg] + (image_2.e - image_1.e)

      x1 = x_diff <= 0 ? -x_diff + 15 : 0
      y1 = y_diff <= 0 ? -y_diff + 15 : 0

      control_point[:x] = x1
      control_point[:X] = x1 + x_diff
      control_point[:y] = y1
      control_point[:Y] = y1 + y_diff

      logger.debug "#{message} #{control_point.n1} <> #{control_point.n2}"
      i = images.first
      3.times.map do
        if control_point.conn_type == :horizontal
          control_point[:x] += 5
          control_point[:X] += 5
          control_point[:y] += i.h * 0.25
          control_point[:Y] += i.h * 0.25
        else
          control_point[:x] += i.w * 0.25
          control_point[:X] += i.w * 0.25
          control_point[:y] += 5
          control_point[:Y] += 5
        end
        control_point.to_s
      end.join
    end
  end
end
