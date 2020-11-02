require 'panomosity/control_point'
require 'panomosity/generalized_neighborhood'
require 'panomosity/image'
require 'panomosity/measure'
require 'panomosity/neighborhood'
require 'panomosity/neighborhood_group'
require 'panomosity/optimisation_variable'
require 'panomosity/optimizer'
require 'panomosity/pair'
require 'panomosity/panorama'
require 'panomosity/panorama_variable'
require 'panomosity/runner'
require 'panomosity/utils'
require 'panomosity/errors'
require 'panomosity/version'
require 'pathname'
require 'fileutils'
require 'optparse'
require 'json'

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

      parser.on('-r', '--report [REPORT]', 'Include a report (when adding calibration control points)') do |report|
        options[:report] = report
      end

      parser.on('--with-masking', 'Use nona-mask to include *_mask.tif files when running "nona_grid"') do |wm|
        options[:with_masking] = wm
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

      parser.on('--verbosity LEVEL', Integer, 'Set verbosity level') do |v|
        options[:verbosity] = v
      end

      parser.on('--report-type TYPE', 'Type of report to create (only when running create_calibration_report)') do |type|
        options[:report_type] = type
      end

      parser.on('--darwin', 'Sets a flag to indicate the operating system') do |type|
        options[:darwin] = type
      end

      parser.on('--version', 'Show the installed version') do
        puts VERSION
        exit
      end

      parser.on('--regional-distance-similarities-count COUNT', Integer, 'Set the minimum amount of regional control point counts for determining similar neighborhoods (default: 3)') do |count|
        options[:regional_distance_similarities_count] = count
      end

      parser.on('--max-reduction-attempts COUNT', Integer, 'Set the max reduction attempts when removing neighborhood outliers (default: 2)') do |count|
        options[:max_reduction_attempts] = count
      end

      desc = <<~DESC
        Set distances to use when determining neighborhood region size in pairs
        Use JSON e.g. '{"x1": 150, "x2": 30}'
        Defaults:
          Vertical pair is x is 10% of image width and y is 100px 
          Horizontal pair is x is 100px and y is 10% of image height
      DESC
      parser.on('--distances [DISTANCE_JSON]', desc) do |distances|
        options[:distances] = JSON.parse(distances) rescue nil
      end

      parser.on('--distances-horizontal [DISTANCE_JSON]', 'Same as above but only affects horizontal image pairs') do |distances|
        options[:regional_distance_similarities_count] = JSON.parse(distances) rescue nil
      end

      parser.on('--distances-vertical [DISTANCE_JSON]', 'Same as above but only affects vertical image pairs') do |distances|
        options[:regional_distance_similarities_count] = JSON.parse(distances) rescue nil
      end

      parser.on('-h', '--help', 'Display this screen') do
        puts parser
        exit
      end

      parser.parse!(arguments)
    end

    # default options
    options[:verbosity] ||= 0
    runner = Runner.new(options)
    runner.run(ARGV[0])
  end

  def self.logger
    if @logger.nil?
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::DEBUG
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}][#{severity}] #{msg}\n"
      end
    end
    @logger
  end
end
