require 'panomosity/utils'

module Panomosity
  class NeighborhoodGroup
    include Panomosity::Utils
    extend Panomosity::Utils

    attr_accessor :center, :total_neighborhoods, :neighborhoods, :control_points, :prdist_avg, :prdist_std, :x_avg,
                  :y_avg

    class << self
      attr_accessor :logger

      def horizontal?
        @type == :horizontal
      end

      def vertical?
        @type == :vertical
      end

      def horizontal
        @horizontal_neighborhood_groups
      end

      def vertical
        @vertical_neighborhood_groups
      end

      def neighborhoods
        horizontal? ? @horizontal_neighborhoods : @vertical_neighborhoods
      end

      def neighborhoods=(value)
        if horizontal?
          @horizontal_neighborhoods = value
        else
          @vertical_neighborhoods = value
        end
      end

      def neighborhood_groups
        horizontal? ? @horizontal_neighborhood_groups : @vertical_neighborhood_groups
      end

      def neighborhood_groups=(value)
        if horizontal?
          @horizontal_neighborhood_groups = value
        else
          @vertical_neighborhood_groups = value
        end
      end

      def parse_info(panorama)
        @panorama = panorama
        @logger = @panorama.logger
      end
    end

    def self.calculate(name: :horizontal, pairs: [])
      @type = name
      default_count = 3
      self.neighborhoods = pairs.map { |p| p.good_neighborhoods_within_std(count: default_count) }.flatten

      if neighborhoods.empty?
        logger.warn 'total neighborhoods came up empty, neighborhood default count to 2'
        default_count = 2
        self.neighborhoods = pairs.map { |p| p.good_neighborhoods_within_std(count: default_count) }.flatten
        raise 'still could not find neighborhoods' if neighborhoods.empty?
      end

      logger.debug "twice reducing #{name} neighborhood std outliers"
      avg, std = *calculate_average_and_std(values: neighborhoods.map(&:prdist_std))
      neighborhoods.select! { |n| (avg - n.prdist_std).abs <= std }
      avg, std = *calculate_average_and_std(values: neighborhoods.map(&:prdist_std))
      neighborhoods.select! { |n| (avg - n.prdist_std).abs <= std }

      self.neighborhood_groups = neighborhoods.map do |neighborhood|
        group = NeighborhoodGroup.new(center: neighborhood, total_neighborhoods: neighborhoods)
        group.calculate
      end

      neighborhood_groups.max_by(5) { |ng| ng.control_points.count }.each do |ng|
        logger.debug "#{ng.prdist_avg} #{ng.prdist_std} #{ng.control_points.count} x#{ng.x_avg} y#{ng.y_avg}"
      end

      self.neighborhood_groups = neighborhood_groups.sort_by { |ng| -ng.control_points.count }
    end

    def self.info

    end

    def initialize(center:, total_neighborhoods:)
      @center = center
      @total_neighborhoods = total_neighborhoods
    end

    def calculate
      @neighborhoods = total_neighborhoods.select { |n| (n.prdist_avg - center.prdist_avg).abs <= center.prdist_std }
      @control_points = neighborhoods.map(&:control_points_within_std).flatten.uniq(&:raw)
      @x_avg = calculate_average(values: control_points.map(&:px))
      @y_avg = calculate_average(values: control_points.map(&:py))
      @prdist_avg = center.prdist_avg
      @prdist_std = center.prdist_std
      self
    end

    def serialize
      delta_cp_x = calculate_average(values: control_points.map { |cp| cp.x2 - cp.x1 })
      delta_cp_y = calculate_average(values: control_points.map { |cp| cp.y2 - cp.y1 })
      {
        x_avg: x_avg,
        y_avg: y_avg,
        prdist_avg: prdist_avg,
        prdist_std: prdist_std,
        cp_count: control_points.count,
        delta_cp_x: delta_cp_x,
        delta_cp_y: delta_cp_y
      }
    end
  end
end
