require 'panomosity/utils'

module Panomosity
  class Pair
    include Panomosity::Utils
    extend Panomosity::Utils

    attr_accessor :pair, :control_points, :neighborhoods, :type

    class << self
      attr_accessor :panorama, :logger

      def horizontal
        @horizontal_pairs
      end

      def vertical
        @vertical_pairs
      end

      def all
        @pairs
      end

      def good_control_points_to_keep(count: 3)
        @pairs.map { |pair| pair.good_control_points_to_keep(count: count) }.flatten.uniq(&:raw)
      end

      def unconnected
        @pairs.select(&:unconnected?).sort_by(&:to_s)
      end

      def without_enough_control_points(ignore_connected: false)
        @pairs.select { |pair| (ignore_connected || pair.connected?) && pair.control_points.count < 3 }
      end
    end

    def self.create_pairs_from_panorama(panorama)
      @panorama = panorama
      @logger = @panorama.logger

      images = @panorama.images
      columns = images.map(&:column).uniq.sort
      rows = images.map(&:row).uniq.sort

      @pairs = []
      # horizontal pair creation
      rows.each do |row|
        columns.each do |column|
          next if column == columns.last
          image_1 = images.find { |i| i.row == row && i.column == column }
          image_2 = images.find { |i| i.row == row && i.column == column.next }
          next if @panorama.calibration? && (image_1.nil? || image_2.nil?)
          control_points = @panorama.control_points.select { |cp| [cp.n1, cp.n2].sort == [image_1.id, image_2.id].sort }
          @pairs << Pair.new([image_1, image_2].sort_by(&:id), control_points: control_points, type: :horizontal)
        end
      end

      # vertical pair creation
      columns.each do |column|
        rows.each do |row|
          next if row == rows.last
          image_1 = images.find { |i| i.column == column && i.row == row }
          image_2 = images.find { |i| i.column == column && i.row == row.next }
          next if @panorama.calibration? && (image_1.nil? || image_2.nil?)
          control_points = @panorama.control_points.select { |cp| [cp.n1, cp.n2].sort == [image_1.id, image_2.id].sort }
          @pairs << Pair.new([image_1, image_2].sort_by(&:id), control_points: control_points, type: :vertical)
        end
      end
    end

    def self.calculate_neighborhoods(panorama, distance: 30)
      create_pairs_from_panorama(panorama)
      @pairs.each { |pair| pair.calculate_neighborhoods(distance: distance) }

      # separate out into horizontal and vertical pairs
      @horizontal_pairs = @pairs.select(&:horizontal?)
      @vertical_pairs = @pairs.select(&:vertical?)

      # sort pairs by average distance first and number of control points descending second
      @horizontal_pairs = @horizontal_pairs.sort_by { |pair| [pair.average_distance, -pair.control_points.count] }
      @vertical_pairs = @vertical_pairs.sort_by { |pair| [pair.average_distance, -pair.control_points.count] }

      log_detailed_neighborhood_info(name: :horizontal, pairs: @horizontal_pairs)
      log_detailed_neighborhood_info(name: :vertical, pairs: @vertical_pairs)
    end

    def self.calculate_neighborhood_groups
      NeighborhoodGroup.parse_info(@panorama)
      NeighborhoodGroup.calculate(name: :horizontal, pairs: @horizontal_pairs)
      NeighborhoodGroup.calculate(name: :vertical, pairs: @vertical_pairs)
    end

    def self.log_detailed_neighborhood_info(name: :horizontal, pairs: [])
      return unless @panorama.options[:verbosity] > 1
      logger.debug "showing #{name} pair information"
      pair = pairs.max_by { |p| p.control_points_of_best_neighborhood.count }
      logger.debug "best #{name} pair #{pair.to_s} found #{pair.control_points_of_best_neighborhood.count} control points"
      pairs.each do |p|
        logger.debug "#{name} pair #{p.to_s} found #{p.control_points_of_best_neighborhood.count} control points"
        p.neighborhoods.each do |n|
          logger.debug "neighborhood centered at #{n.center.x1},#{n.center.y1}: #{n.control_points.count} control points"
          logger.debug "neighborhood centered at #{n.center.x1},#{n.center.y1}: prdist #{n.prdist_avg},#{n.prdist_std} prx #{n.prx_avg},#{n.prx_std} pry #{n.pry_avg},#{n.pry_std}"
          n.control_points.each { |point| logger.debug point.detailed_info }
        end
      end
    end

    def self.info
      logger.debug "total number of control points: #{@pairs.map(&:control_points).flatten.count}"
      logger.debug 'displaying horizontal pair info'
      logger.debug "total number of horizontal control points: #{@horizontal_pairs.map(&:control_points).flatten.count}"
      @horizontal_pairs.each do |pair|
        logger.debug pair.info
        logger.debug "total number of control points: #{pair.control_points.count}"
        x_dist, x_std = *calculate_average_and_std(values: pair.control_points.map(&:prx))
        y_dist, y_std = *calculate_average_and_std(values: pair.control_points.map(&:pry))
        dist, std = *calculate_average_and_std(values: pair.control_points.map(&:prdist))
        logger.debug "control points: x_dist,x_std: #{x_dist},#{x_std} | y_dist,y_std: #{y_dist},#{y_std} | dist,std: #{dist},#{std}"
        logger.debug "total number of neighborhoods: #{pair.neighborhoods.count}"
        logger.debug "total number single cp neighborhoods: #{pair.neighborhoods.select{|n| n.control_points.count == 1}.count}"
        logger.debug "total number generated control points: #{pair.control_points.select(&:generated?).count}"
        pair.neighborhoods.each do |neighborhood|
          logger.debug neighborhood.info
          logger.debug "neighborhood: distance,pair_distance: #{neighborhood.distance},#{neighborhood.pair_distance} | total number of control points: #{neighborhood.control_points.count}"
          logger.debug "neighborhood: center prdist: #{neighborhood.center.prdist} | total number of control points within std: #{neighborhood.control_points_within_std.count}"
        end
      end
      logger.debug 'displaying vertical pair info'
      logger.debug "total number of vertical control points: #{@vertical_pairs.map(&:control_points).flatten.count}"
      @vertical_pairs.each do |pair|
        logger.debug pair.info
        logger.debug "total number of control points: #{pair.control_points.count}"
        x_dist, x_std = *calculate_average_and_std(values: pair.control_points.map(&:prx))
        y_dist, y_std = *calculate_average_and_std(values: pair.control_points.map(&:pry))
        dist, std = *calculate_average_and_std(values: pair.control_points.map(&:prdist))
        logger.debug "control points: x_dist,x_std: #{x_dist},#{x_std} | y_dist,y_std: #{y_dist},#{y_std} | dist,std: #{dist},#{std}"
        logger.debug "total number of neighborhoods: #{pair.neighborhoods.count}"
        logger.debug "total number single cp neighborhoods: #{pair.neighborhoods.select{|n| n.control_points.count == 1}.count}"
        logger.debug "total number generated control points: #{pair.control_points.select(&:generated?).count}"
        pair.neighborhoods.each do |neighborhood|
          logger.debug neighborhood.info
          logger.debug "neighborhood: distance,pair_distance: #{neighborhood.distance},#{neighborhood.pair_distance} | total number of control points: #{neighborhood.control_points.count}"
          logger.debug "neighborhood: center prdist: #{neighborhood.center.prdist} | total number of control points within std: #{neighborhood.control_points_within_std.count}"
        end
      end
    end

    def initialize(pair, control_points: [], type: nil)
      @pair = pair
      @control_points = control_points
      @neighborhoods = []
      @type = type
    end

    def to_s
      pair.map(&:id).to_s.gsub(' ', '')
    end

    def ==(other)
      to_s == other.to_s
    end

    def info
      "#{to_s}(#{type}) image_1 d,e: #{pair.first.d},#{pair.first.e} | image_2 d,e: #{pair.last.d},#{pair.last.e}"
    end

    def horizontal?
      @type == :horizontal || (control_points.first && control_points.first.conn_type == :horizontal)
    end

    def vertical?
      @type == :vertical || (control_points.first && control_points.first.conn_type == :vertical)
    end

    def connected?
      !unconnected?
    end

    def unconnected?
      control_points.empty?
    end

    def first_image
      pair.first
    end

    def last_image
      pair.last
    end

    def average_distance
      calculate_average(values: control_points.map(&:prdist), ignore_empty: true)
    end

    def calculate_neighborhoods(distance: 30)
      @neighborhoods = control_points.map do |cp|
        neighborhood = Neighborhood.new(center: cp, pair: self, distance: distance)
        neighborhood.calculate
      end
    end

    # gets all control points for neighborhoods with a good std of distance
    def good_neighborhoods_within_std(count: 3)
      @neighborhoods.select { |n| n.control_points_within_std.count >= count }
    end

    def good_control_points_to_keep(count: 3)
      control_points_to_keep = good_neighborhoods_within_std(count: count).map(&:control_points_within_std).flatten.uniq(&:raw)

      # Keep all our control points if we have less than 10
      if control_points.count >= 10
        ratio = control_points_to_keep.count.to_f / control_points.count
        if ratio < 0.2
          Panomosity.logger.warn "#{to_s} keeping less than 20% (#{(ratio*100).round(4)}%) of #{control_points.count} control points. Reverting and keeping all control points"
          control_points
        else
          control_points_to_keep
        end
      else
        control_points
      end
    end

    def best_neighborhood
      @best_neighborhood ||= @neighborhoods.max_by { |n| n.control_points.count }
    end

    def control_points_of_best_neighborhood
      best_neighborhood ? best_neighborhood.control_points : []
    end

    def attributes
      x_avg, x_std = *calculate_average_and_std(values: control_points.map(&:px), ignore_empty: true)
      y_avg, y_std = *calculate_average_and_std(values: control_points.map(&:py), ignore_empty: true)
      dist_avg, dist_std = *calculate_average_and_std(values: control_points.map(&:pdist), ignore_empty: true)
      i1 = control_points.first.n1
      i2 = control_points.first.n2
      {
        id: [i1, i2], n: i1, N: i2, count: control_points.count, type: type,
        x_avg: x_avg, x_std: x_std, y_avg: y_avg, y_std: y_std, dist_avg: dist_avg, dist_std: dist_std
      }
    end
  end
end
