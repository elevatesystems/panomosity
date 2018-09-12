# Exmaple of an image line
# i w2448 h3264 f0 v=0 Ra=0 Rb=0 Rc=0 Rd=0 Re=0 Eev6.433 Er1 Eb1 r0 p0 y0 TrX0.88957152 TrY0.79560269 TrZ1 Tpy0 Tpp0 j0 a=0 b=0 c=0 d=0 e=0 g0 t0 Va=0 Vb=0 Vc=0 Vd=0 Vx=0 Vy=0  Vm5 n"WZ8ppTx9PtcxASB3hbeeuS6Z"\n

module Panomosity
  class Image
    @@attributes = %i(w h f v Ra Rb Rc Rd Re Eev Er Eb r p y TrX TrY TrZ Tpy Tpp j a b c d e g t Va Vb Vc Vd Vx Vy Vm n)
    @@equaled_attributes = %i(v Ra Rb Rc Rd Re a b c d e Va Vb Vc Vd Vx Vy)

    def self.parse(pto_file)
      id = 0
      @images = pto_file.each_line.map do |line|
        image = parse_line(line, id)
        if image
          id += 1
          image
        end
      end.compact

      calculate_dimensions
      @images
    end

    def self.calculate_dimensions(fov = nil)
      @fov = fov || 45.2
      lam = (90 - (@fov / 2.0)) * (Math::PI / 180.0)
      @panosphere = (Math.tan(lam) * 0.5 * 0.5)
      _, @x_offset = @images.map(&:TrX).minmax
      _, @y_offset = @images.map(&:TrY).minmax
    end

    def self.all
      @images
    end

    def self.panosphere
      @panosphere
    end

    def self.x_offset
      @x_offset
    end

    def self.y_offset
      @y_offset
    end

    def self.parse_line(line, id = 0)
      parts = line.split(' ')
      if parts.first == 'i'
        data = parts.each_with_object({}) do |part, hash|
          attribute = @@attributes.find { |attr| part[0..(attr.to_s.length-1)] == attr.to_s }
          next unless attribute
          hash[attribute] = part.sub(attribute.to_s, '')
        end

        # Sanitization
        data.each { |key, value| data[key] = value.sub(/\A=/, '') }
        data[:n] = data[:n].gsub('"', '')
        data[:id] = id
        data[:raw] = line

        new data
      end
    end

    def initialize(attributes)
      @attributes = attributes
      # conform data types
      @attributes.each do |key, value|
        next if %i(n id raw).include?(key)
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

    (@@attributes + %i(raw id)).each do |attr|
      define_method(attr) do
        @attributes[attr]
      end

      define_method(:"#{attr}=") do |value|
        @attributes[attr] = value
      end
    end

    alias_method :width, :w
    alias_method :height, :h
    alias_method :name, :n

    def normal_x
      self[:TrX] * self.class.panosphere * width
    end

    def normal_y
      self[:TrY] * self.class.panosphere * height
    end

    def to_s(options = {})
      subline_values = (@@attributes - %i(Vm n)).map do |attribute|
        value = self.send(attribute)
        if @@equaled_attributes.include?(attribute) && !options[:without_equal_signs]
          if value == 0.0
            "#{attribute}=#{value.to_i}"
          else
            "#{attribute}#{value}"
          end
        else
          "#{attribute}#{value}"
        end
      end
      %Q(i #{subline_values.join(' ')}  Vm#{self[:Vm]} n"#{self[:n]}"\n)
    end

    # Gets the value of TrX and TrY and sets them as d and e
    def convert_position!
      trx = self[:TrX]
      try = self[:TrY]

      self[:TrX] = 0
      self[:TrY] = 0
      self[:TrZ] = 0

      # To fix an issue with pto reading files ignoring attributes that have a =0
      trx = '0.0' if trx == 0.0
      try = '0.0' if try == 0.0

      self[:d] = trx
      self[:e] = try
      self
    end

    def to_cartesian(x1, y1)
      px = (w / 2.0) - x1 + d
      py = (h / 2.0) - y1 + e
      rad = (w / 2.0) / Math.tan((v * Math::PI / 180) / 2)
      r = self.r * Math::PI / 180
      p = self.p * Math::PI / 180
      y = self.y * Math::PI / 180

      # Derived from multiplication of standard roll, pitch, and yaw matrices by the point vector (rad, px, py)
      point = [Math.cos(p) * Math.cos(y) * rad - Math.sin(y) * Math.cos(p) * px + Math.sin(p) * py,
               Math.sin(r) * Math.sin(p) * Math.cos(y) * rad + Math.sin(y) * Math.cos(r) * rad - Math.sin(r) * Math.sin(p) * Math.sin(y) * px + Math.cos(r) * Math.cos(y) * px - Math.sin(r) * Math.cos(p) * py,
               -Math.sin(p) * Math.cos(r) * Math.cos(y) * rad + Math.sin(r) * Math.sin(y) * rad + Math.sin(p) * Math.sin(y) * Math.cos(r) * px + Math.sin(r) * Math.cos(y) * px + Math.cos(r) * Math.cos(p) * py]
      magnitude = Math.sqrt(point[0] ** 2 + point[1] ** 2 + point[2] ** 2)
      normalized_point = [point[0] / magnitude, point[1] / magnitude, point[2] / magnitude]
      normalized_point
    end
  end
end
