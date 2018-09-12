# Example of a control point line
# c n26 N26 x887.4 y1056.72 X1128.12 Y1077.12 t2

module Panomosity
  class ControlPoint
    @@attributes = %i(n N x y X Y t)

    def self.parse(pto_file, cp_type: nil, compact: false)
      @control_points = pto_file.each_line.map do |line|
        if compact
          cp_data = line.split(',').map { |part| part.split(' ') }.flatten
          n1, x1, y1, n2, x2, y2, type, dist = *cp_data.to_a.map(&:to_f)
          new(n: n1, N: n2, x: x1, y: y1, X: x2, Y: y2, t: type, dist: dist, raw: line)
        else
          parse_line(line)
        end
      end.compact

      case cp_type
        when :line
          @control_points.select!(&:line?)
        when :normal
          @control_points.select!(&:normal?)
        when :vertical
          @control_points.select!(&:vertical?)
        when :horizontal
          @control_points.select!(&:horizontal?)
        else
          @control_points
      end

      @control_points
    end

    def self.get_detailed_info(pto_file_path, cp_type: nil)
      exe_dir = File.expand_path('../../exe', File.dirname(__FILE__))
      control_point_info_executable = File.join(exe_dir, 'control_point_info.pl')
      result = `#{control_point_info_executable} --input #{pto_file_path}`
      parse(result, cp_type: cp_type, compact: true)
    end

    def self.all
      @control_points
    end

    def self.parse_line(line)
      parts = line.split(' ')
      if parts.first == 'c'
        data = parts.each_with_object({}) do |part, hash|
          attribute = @@attributes.find { |attr| part[0] == attr.to_s }
          next unless attribute
          hash[attribute] = part.sub(attribute.to_s, '')
        end

        data[:raw] = line
        data[:dist] = nil

        new data
      end
    end

    def self.merge(first_set_control_points, second_set_control_points)
      @control_points = first_set_control_points.map do |cp1|
        similar_control_point = second_set_control_points.find { |cp2| cp1 == cp2 }
        cp1.dist = similar_control_point.dist
        cp1
      end
    end

    def initialize(attributes)
      @attributes = attributes
      # conform data types
      @attributes.each do |key, value|
        next if %i(raw).include?(key)
        next unless value.is_a?(String)
        if value.respond_to?(:include?) && value.include?('.')
          @attributes[key] = value.to_f
        else
          @attributes[key] = value.to_i
        end
      end
    end

    def [](key)
      @attributes[key]
    end

    def []=(key, value)
      @attributes[key] = value
    end

    (@@attributes + %i(raw dist)).each do |attr|
      define_method(attr) do
        @attributes[attr]
      end

      define_method(:"#{attr}=") do |value|
        @attributes[attr] = value
      end
    end

    alias_method :type, :t
    alias_method :n1, :n
    alias_method :n2, :N
    alias_method :x1, :x
    alias_method :x2, :X
    alias_method :y1, :y
    alias_method :y2, :Y

    def normal?
      type == 0
    end

    def vertical?
      type == 1
    end

    def horizontal?
      type == 2
    end

    def line?
      vertical? || horizontal?
    end

    def to_s
      line_values = @@attributes.map { |attribute| "#{attribute}#{self.send(attribute)}" }
      "c #{line_values.join(' ')}\n"
    end

    def ==(o)
      n1 == o.n1 &&
        n2 == o.n2 &&
        x1.floor == o.x1.floor &&
        x2.floor == o.x2.floor &&
        y1.floor == o.y1.floor &&
        y2.floor == o.y2.floor
    end
  end
end
