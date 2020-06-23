require 'panomosity/utils'

module Panomosity
  class GeneralizedNeighborhood
    include Panomosity::Utils

    CONTROL_POINT_ATTRIBUTES = [:dist_avg, :dist_std, :x_avg, :x_std, :y_avg, :y_std]
    ATTRIBUTES = [:center, :scope, :control_points, :count] + CONTROL_POINT_ATTRIBUTES
    DEFAULT_DISTANCE = 100

    attr_reader :measure, :options
    attr_accessor *ATTRIBUTES

    class << self
      include Panomosity::Utils

      attr_accessor :options, :neighborhoods, :horizontal_similar_neighborhoods, :vertical_similar_neighborhoods, :horizontal_neighborhoods_by_similar_neighborhood, :vertical_neighborhoods_by_similar_neighborhood

      def logger
        @logger ||= Panomosity.logger
      end

      def attributes
        { name: name }
      end

      def horizontal
        horizontal_neighborhoods_by_similar_neighborhood
      end

      def vertical
        vertical_neighborhoods_by_similar_neighborhood
      end

      def calculate_all(panorama:, options: {})
        @neighborhoods = []
        @options = options

        Pair.create_pairs_from_panorama(panorama)
        calculate_from_pairs
        calculate_from_neighborhoods(type: :horizontal)
        calculate_from_neighborhoods(type: :vertical)

        @neighborhoods
      end

      def calculate_from_pairs
        logger.debug 'calculating neighborhoods from pairs'
        Pair.all.each do |pair|
          control_points = pair.control_points.select(&:not_generated?)
          control_points.each do |control_point|
            base_params = { center: control_point, scope: pair, options: options }
            position_params = { measure: { type: :position } }
            neighborhood = calculate_neighborhood(**base_params.merge(position_params))
            pair.generalized_neighborhoods << neighborhood
            distance_params = { measure: { type: :distance, distances: { x1: neighborhood.dist_std } } }
            distance_neighborhood = calculate_neighborhood(**base_params.merge(distance_params))
            neighborhood.reference = distance_neighborhood
            pair.generalized_neighborhoods << distance_neighborhood
          end
        end
      end

      def calculate_from_neighborhoods(type:)
        count = options[:regional_distance_similarities_count] || 3
        attempts = options[:max_reduction_attempts] || 2

        # calculates similar neighborhoods based on the regional control point distances by pair
        calculate_similar_neighborhoods(type: type, count: count)
        if neighborhoods.empty?
          logger.warn 'total neighborhoods came up empty, neighborhood default count to 2'
          calculate_similar_neighborhoods(type: type, count: 2)
          raise 'still could not find neighborhoods' if neighborhoods.empty?
        end

        std_outlier_reduction(type: type, max_reduction_attempts: attempts)
        calculate_neighborhoods_by_similar_neighborhood(type: type)
      end

      def calculate_neighborhood(center:, scope:, options:, measure: {})
        neighborhood = new(center: center, scope: scope, options: options)
        neighborhood.update_measure(measure)
        @neighborhoods << neighborhood.calculate
        neighborhood
      end

      def similar_neighborhoods(type: :horizontal)
        type == :horizontal ? @horizontal_similar_neighborhoods : @vertical_similar_neighborhoods
      end

      def neighborhoods_by_similar_neighborhood(type: :horizontal)
        type == :horizontal ? @horizontal_neighborhoods_by_similar_neighborhood : @vertical_neighborhoods_by_similar_neighborhood
      end

      def calculate_similar_neighborhoods(type: :horizontal, count: 3)
        similar_neighborhoods = neighborhoods.select(&:measure_position?).select(&:"#{type}?").select do |neighborhood|
          neighborhood.scope.similar_neighborhoods << neighborhood if neighborhood.reference.count >= count
        end
        self.send(:"#{type}_similar_neighborhoods=", similar_neighborhoods)
      end

      def std_outlier_reduction(type: :horizontal, max_reduction_attempts: 2, reduction_attempts: 0)
        return if reduction_attempts >= max_reduction_attempts
        logger.debug "twice reducing #{type} neighborhood std outliers"
        avg, std = *calculate_average_and_std(values: similar_neighborhoods(type: type).map(&:dist_std))
        similar_neighborhoods(type: type).select! { |n| (avg - n.dist_std).abs <= std }
        std_outlier_reduction(type: type, max_reduction_attempts: max_reduction_attempts, reduction_attempts: reduction_attempts + 1)
      end

      def calculate_neighborhoods_by_similar_neighborhood(type: :horizontal)
        instance_variable_set("@#{type}_neighborhoods_by_similar_neighborhood", [])
        similar_neighborhoods(type: type).each do |neighborhood|
          base_params = { center: neighborhood, scope: self, options: options }
          distance_params = { measure: { type: :distance, distances: { x1: neighborhood.dist_std } } }
          neighborhoods_by_similar_neighborhood(type: type) << calculate_neighborhood(**base_params.merge(distance_params))
        end

        neighborhoods_by_similar_neighborhood(type: type).sort_by! { |n| -n.count }
        neighborhoods_by_similar_neighborhood(type: type).max_by(5) { |n| n.count }.each do |n|
          logger.debug "#{n.dist_avg} #{n.dist_std} #{n.count} x#{n.x_avg} y#{n.y_avg}"
        end
      end
    end

    def initialize(center:, scope:, options: {})
      @center = center
      @scope = scope
      @options = options
      @measure = Measure.new
    end

    def id
      @id
    end

    def id=(id)
      @id = id
    end

    def reference
      @reference
    end

    def reference=(reference)
      @reference = reference
    end

    def pair_scope?
      scope.class.name == 'Panomosity::Pair'
    end

    def neighborhood_scope?
      scope.class.name == self.class.name
    end

    def measure_position?
      measure.position?
    end

    def measure_distance?
      measure.distance?
    end

    def horizontal?
      pair_scope? ? scope.horizontal? : center.horizontal?
    end

    def vertical?
      pair_scope? ? scope.vertical? : center.vertical?
    end

    def type
      horizontal? ? :horizontal : :vertical
    end

    def update_measure(params)
      measure.update(params)
      set_distance_defaults
      set_measure_defaults
    end

    def distances_from_options(type: :horizontal)
      if type == :both
        options.fetch(:distances, {})
      else
        options[:distances]&.fetch(type, {}) || {}
      end
    end

    def set_distance_defaults
      return unless measure_position?

      measure.update_distances(distances_from_options(type: :both))

      if scope.horizontal?
        measure.update_distances(x2: (scope.first_image.h * 0.1).round)
        measure.update_distances(distances_from_options(type: :horizontal))
      else
        measure.update_distances(x1: (scope.first_image.w * 0.1).round)
        measure.update_distances(distances_from_options(type: :vertical))
      end

      measure.distances[:x1] ||= DEFAULT_DISTANCE
      measure.distances[:x2] ||= DEFAULT_DISTANCE
    end

    def set_measure_defaults
      center_values = if measure_position?
        { x1: center.x1, x2: center.y1 }
      elsif pair_scope?
        { x1: center.pdist }
      else
        { x1: center.dist_avg }
      end

      measure.update(center: center_values)
    end

    def calculate
      if pair_scope?
        elements = scope.control_points.select(&:not_generated?)

        @control_points = if measure_position?
          elements.select { |cp| measure.includes?(cp.x1, cp.y1) }
        else
          elements.select { |cp| measure.includes?(cp.pdist) }
        end
      else
        @neighborhoods = scope.similar_neighborhoods(type: center.type).select { |n| measure.includes?(n.dist_avg) }
        distance_neighborhoods = @neighborhoods.map(&:reference)
        @control_points = distance_neighborhoods.map(&:control_points).flatten.uniq(&:raw)
      end

      @dist_avg, @dist_std = *calculate_average_and_std(values: control_points.map(&:pdist), ignore_empty: true)
      @x_avg, @x_std = *calculate_average_and_std(values: control_points.map(&:px), ignore_empty: true)
      @y_avg, @y_std = *calculate_average_and_std(values: control_points.map(&:py), ignore_empty: true)
      @count = control_points.count

      self
    end

    def attributes
      attributes = CONTROL_POINT_ATTRIBUTES.reduce({}) { |h, k| h.merge!({ k => self.send(k) }) }
      measure_attributes = measure.attributes.reduce({}) do |hash, (key, value)|
        hash["measure_#{key}"] = value
        hash
      end
      if pair_scope?
        center_id = center[:id]
        scope_id = [scope.control_points.first.n1, scope.control_points.first.n2]
        scope_name = 'pair'
      else
        center_id = center.id
        scope_id = nil
        scope_name = 'neighborhood'
      end
      attributes.merge!(measure_attributes)
      attributes.merge!(id: id, center: center_id, scope_id: scope_id, scope_name: scope_name, type: type, control_points: control_points.map{|c| c[:id]})
      attributes
    end
  end
end
