require 'panomosity/control_point'
require 'panomosity/image'
require 'panomosity/optimisation_variable'
require 'panomosity/optimizer'
require 'panomosity/panorama'
require 'panomosity/panorama_variable'
require 'panomosity/runner'
require 'panomosity/utils'
require 'panomosity/version'
require 'pathname'
require 'fileutils'
require 'optparse'

module Panomosity
  def self.parse(arguments)
    options = {}
    OptionParser.new do |parser|
      parser.banner = 'Usage: panomosity command [options]'
      parser.separator ''
      parser.separator 'Specific options:'

      parser.on('-i', '--input PTO', 'Input PTO file') do |pto|
        options[:input] = pto
      end

      parser.on('-o', '--output PTO', 'Output PTO file') do |pto|
        options[:output] = pto
      end

      parser.on('-c', '--csv [CSV]', 'CSV file for reference') do |csv|
        options[:csv] = csv
      end

      parser.on('-k', '--compare [PTO]', 'Compare PTO file for reference') do |pto|
        options[:compare] = pto
      end

      parser.on('--without-cropping', 'Do not crop when running "crop_centers" (usually when the original run failed)') do |wc|
        options[:without_cropping] = wc
      end

      parser.on('--remove-equal-signs', 'Remove equal signs when running "convert_equaled_image_parameters" (necessary when parsing the PTO file using Panotools)') do |eq|
        options[:remove_equal_signs] = eq
      end

      parser.on('--max-removal FRAC', Float, 'Max fraction of control points to be removed when running "clean_control_points" that are statistical outliers') do |mr|
        options[:max_removal] = mr
      end

      parser.on('--res RES', 'Resolution of images for nona_grid') do |res|
        options[:res] = res
      end

      parser.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
        options[:verbose] = v
      end

      parser.on('-h', '--help', 'Display this screen') do
        puts parser
        exit
      end

      parser.parse!(arguments)
    end

    runner = Runner.new(options)
    runner.run(ARGV[0])
  end
end
