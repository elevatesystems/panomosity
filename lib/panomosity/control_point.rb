# Example of a control point line
# c n26 N26 x887.4 y1056.72 X1128.12 Y1077.12 t2

module Panomosity
  class ControlPoint
    @@attributes = %i(n N x y X Y t g)
    @@calculated_attributes = %i(dist px py pdist prx pry prdist conn_type i1 i2)

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

    def self.calculate_distances(images, panorama_variable)
      @control_points.each do |cp|
        image1 = images.find { |i| cp.n1 == i.id }
        image2 = images.find { |i| cp.n2 == i.id }
        point1 = image1.to_cartesian(cp.x1, cp.y1)
        point2 = image2.to_cartesian(cp.x2, cp.y2)

        product = point1[0] * point2[0] + point1[1] * point2[1] + point1[2] * point2[2]
        product = 1.0 if product > 1.0
        angle = Math.acos(product)
        radius = (panorama_variable.w / 2.0) / Math.tan((panorama_variable.v * Math::PI / 180) / 2)

        distance = angle * radius
        cp.dist = distance

        # pixel distance
        x1 = (image1.w / 2.0) - cp.x1 + image1.d
        y1 = (image1.h / 2.0) - cp.y1 + image1.e
        x2 = (image2.w / 2.0) - cp.x2 + image2.d
        y2 = (image2.h / 2.0) - cp.y2 + image2.e

        cp.px = x1 - x2
        cp.py = y1 - y2
        cp.pdist = Math.sqrt(cp.px ** 2 + cp.py ** 2)

        # pixel distance including roll
        r = image1.r * Math::PI / 180
        cp.prx = image1.d - image2.d + Math.cos(r) * (cp.x2 - cp.x1) - Math.sin(r) * (cp.y2 - cp.y1)
        cp.pry = image1.e - image2.e + Math.cos(r) * (cp.y2 - cp.y1) - Math.sin(r) * (cp.x2 - cp.x1)
        cp.prdist = Math.sqrt(cp.prx ** 2 + cp.pry ** 2)

        cp.conn_type = image1.column == image2.column ? :vertical : :horizontal
        cp.i1 = image1
        cp.i2 = image2
      end
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

    (@@attributes + @@calculated_attributes + %i(raw)).each do |attr|
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

    def generated?
      !g.nil?
    end

    def not_generated?
      !generated?
    end

    def to_s
      attrs = generated? ? @@attributes : (@@attributes - %i(g))
      line_values = attrs.map { |attribute| "#{attribute}#{self.send(attribute)}" }
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

    def recalculate_pixel_distance
      r = i1.r * Math::PI / 180
      self.prx = i1.d - i2.d + Math.cos(r) * (x2 - x1) - Math.sin(r) * (y2 - y1)
      self.pry = i1.e - i2.e + Math.cos(r) * (y2 - y1) - Math.sin(r) * (x2 - x1)
      self.prdist = Math.sqrt(prx ** 2 + pry ** 2)
    end

    def detailed_info
      "#{to_s.sub(/\n/, '')} dist #{dist.round(4)} pixel_dist #{px.round(4)},#{py.round(4)},#{pdist.round(4)} pixel_r_dist #{prx.round(4)},#{pry.round(4)},#{prdist.round(4)} conn_type #{conn_type}"
    end

    def attributes
      @attributes
    end
  end
end
