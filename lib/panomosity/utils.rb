module Panomosity
  module Utils
    def calculate_average_and_std(name: 'value', values: [], logger: nil, ignore_empty: false)
      return [0, 0] if ignore_empty && values.empty?
      average_value = calculate_average(name: name, values: values, logger: logger, ignore_empty: ignore_empty)

      if values.count == 1
        value_std = 0.0
      else
        value_std = Math.sqrt(values.map { |v| (v - average_value) ** 2 }.reduce(:+) / (values.count - 1))
      end
      logger.debug "#{name} std: #{value_std}" if logger

      [average_value, value_std]
    end

    def calculate_average(name: 'value', values: [], logger: nil, ignore_empty: false)
      return 0 if ignore_empty && values.empty?
      average_value = values.reduce(:+).to_f / values.count
      logger.debug "average #{name}: #{average_value}" if logger
      average_value
    end

    def remove_outliers(method: :value, values: [], logger: nil)
      avg, std = *calculate_average_and_std(values: values.map(&method))
      while std >= 0.1
        values.select! { |c| (avg - c.send(method)).abs <= std }
        avg, std = *calculate_average_and_std(values: values.map(&method))
        logger.debug [avg , std, values.count].to_s if logger
      end
      values
    end
  end
end
