module Panomosity
  class OptimisationVariable
    START_LINE = 'v'
    @@attributes = %i(w h f v Ra Rb Rc Rd Re Eev Er Eb r p y TrX TrY TrZ Tpy Tpp j a b c d e g t Va Vb Vc Vd Vx Vy Vm n)

    def self.parse(pto_file)
      @optimization_variables = pto_file.each_line.map { |line| parse_line(line) }.compact
    end

    def self.all
      @optimization_variables
    end

    def self.parse_line(line)
      parts = line.split(' ')
      if parts.first == START_LINE
        parts = parts[1..(parts.count-1)]
        data = parts.each_with_object({}) do |part, hash|
          attribute = @@attributes.find { |attr| part[0] == attr.to_s }
          next unless attribute
          hash[attribute] = part.sub(attribute.to_s, '')
        end

        data[:raw] = line

        new data
      end
    end

    def initialize(attributes)
      @attributes = attributes
      # conform data types
      @attributes.each do |key, value|
        next if %i(raw).include?(key)
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

    (@@attributes + %i(raw)).each do |attr|
      define_method(attr) do
        @attributes[attr]
      end

      define_method(:"#{attr}=") do |value|
        @attributes[attr] = value
      end
    end

    def to_s
      line_values = @@attributes.map { |attribute| "#{attribute}#{self.send(attribute)}" if self.send(attribute) }
      "v #{line_values.compact.join(' ')}\n"
    end

    def attributes
      @attributes.keep_if { |k, _| !%i(raw).include?(k) }
    end
  end
end
