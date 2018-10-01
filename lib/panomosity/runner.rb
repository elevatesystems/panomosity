require 'logger'

module Panomosity
  class Runner
    include Panomosity::Utils

    attr_reader :logger

    AVAILABLE_COMMANDS = %w(
      check_position_changes
      clean_control_points
      convert_equaled_image_parameters
      convert_horizontal_lines
      convert_translation_parameters
      crop_centers
      fix_conversion_errors
      fix_unconnected_image_pairs
      generate_border_line_control_points
      get_detailed_control_point_info
      merge_image_parameters
      optimize
      prepare_for_pr0ntools
      remove_anchor_variables
      standardize_roll
    )

    def initialize(options)
      @options = options
      @input = options[:input]
      @output = options[:output]
      @csv = options[:csv]
      @compare = options[:compare]
      @input_file = File.new(@input, 'r').read rescue puts('You must have at least one argument')
      @output_file = File.new(@output, 'w') if @output
      @csv_file = File.new(@csv, 'r').read if @csv
      @compare_file = File.new(@compare, 'r').read if @compare
      @logger = Logger.new(STDOUT)

      if options[:verbose]
        @logger.level = Logger::DEBUG
      else
        @logger.level = Logger::INFO
      end

      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}][#{severity}] #{msg}\n"
      end
    end

    def run(command)
      if AVAILABLE_COMMANDS.include?(command)
        send(command)
      else
        logger.info "commands include:\n#{AVAILABLE_COMMANDS.join("\n")}"
      end
    end

    def check_position_changes
      logger.info 'checking position changes'
      original_images = Image.parse(@input_file)
      changed_images = Image.parse(@compare_file)
      threshold = 0.10
      images = original_images.zip(changed_images)
      changes_x = images.select do |original, changed|
        ratio_x = original.d / changed.d
        changed_x = (1 - ratio_x.abs).abs
        changed_x > threshold
      end
      changes_y = images.select do |original, changed|
        ratio_y = original.e / changed.e
        changed_y = (1 - ratio_y.abs).abs
        changed_y > threshold
      end

      @lines = @input_file.each_line.map do |line|
        variable = OptimisationVariable.parse_line(line)
        next line unless variable
        if variable.d && changes_x.find { |original, _| original.id.to_s == variable.d }
          logger.debug "Removing #{variable.to_s}"
        elsif variable.e && changes_y.find { |original, _| original.id.to_s == variable.e }
          logger.debug "Removing #{variable.to_s}"
        else
          next line
        end
      end

      save_file
    end

    def clean_control_points
      logger.info 'cleaning control points'
      # Since this is very exact, having many outliers in control points distances will cause errors
      panorama = Panorama.new(@input_file, logger)
      bad_control_points = panorama.clean_control_points_neighborhoods(@options)

      logger.info "removing #{bad_control_points.count} control points"
      @lines = @input_file.each_line.map do |line|
        control_point = ControlPoint.parse_line(line)
        # skip this control point if we found it
        if control_point && bad_control_points.find { |bad_cp| bad_cp.raw == control_point.raw }
          next
        else
          next line
        end
      end.compact

      save_file
    end

    def convert_equaled_image_parameters
      logger.info 'converting equaled image parameters'
      images = Image.parse(@input_file)
      @lines = @input_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        if image
          if @options[:remove_equal_signs]
            image.to_s(without_equal_signs: true)
          else
            image.to_s
          end
        else
          next line
        end
      end.compact

      save_file
    end

    def convert_horizontal_lines
      logger.info 'converting horizontal lines'
      @lines = @input_file.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp && cp.vertical?
          cp.t = 2
          cp.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def convert_translation_parameters
      logger.info 'converting translation parameters'
      images = Image.parse(@input_file)

      @lines = @input_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        next if line[0] == 'v'
        next line unless image
        image.convert_position!
        if image.id == images.sort_by(&:id).last.id
          image.to_s +
            "\n" +
            "# Variable lines\n" +
            images.map { |i| i.id == 0 ? nil : "v d#{i.id} e#{i.id}\n" }.compact.join +
            "v\n" +
            "\n"
        else
          image.to_s
        end

      end.compact

      save_file
    end

    # Uses image magick to crop centers
    def crop_centers
      logger.info 'cropping centers'
      scale_factor = @csv_file.split(/\n/).first.split(',').last.to_f
      percent = (scale_factor*100).round
      logger.debug "cropping to #{percent}%"
      unless @options[:without_cropping]
        images = Image.parse(@input_file)
        images.each do |image|
          geometry = `identify -verbose #{image.name} | grep Geometry`.strip
          _, width, height = *geometry.match(/(\d{2,5})x(\d{2,5})(\+|\-)\d{1,5}(\+|\-)\d{1,5}/)
          width_offset = (width.to_f * (1 - scale_factor) / 2).round
          height_offset = (height.to_f * (1 - scale_factor) / 2).round
          logger.debug "cropping #{image.name}"
          `convert #{image.name} -crop "#{percent}%x#{percent}%+#{width_offset}+#{height_offset}" #{image.name}`
        end
      end

      # Since all images have been cropped, we need to change d,e params to move images based on how much was cropped
      # Re-run commands that have been run at this point
      logger.info 'rerunning commands'
      @new_input = 'project_converted_translation_cropped.pto'
      `match-n-shift --input #{@csv} -o project_cropped.pto`
      `pto_var --opt=TrX,TrY project_cropped.pto -o project_pto_var_cropped.pto`
      runner = Runner.new(@options.merge(input: 'project_pto_var_cropped.pto', output: @new_input))
      runner.run('convert_translation_parameters')
      `pano_modify -p 0 --fov=AUTO -o #{@new_input} #{@new_input}`

      logger.info "Read new #{@new_input}"
      # Read new input pto file
      @input_file = File.new(@new_input, 'r').read
      images = Image.parse(@input_file)
      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort

      d_diffs = []
      ds.each_with_index do |_, i|
        next if i == 0
        d_diffs.push((ds[i] - ds[i-1]).abs * (1-scale_factor))
      end

      e_diffs = []
      es.each_with_index do |_, i|
        next if i == 0
        e_diffs.push((es[i] - es[i-1]).abs * (1-scale_factor))
      end

      d_map = Hash[ds.map.with_index { |d, i| i == 0 ? [d, d] : [d, d - d_diffs[0..(i-1)].reduce(:+)] }]
      e_map = Hash[es.map.with_index { |e, i|  i == 0 ? [e, e] : [e, e - e_diffs[0..(i-1)].reduce(:+)] }]

      d_min, d_max = d_map.values.minmax
      e_min, e_max = e_map.values.minmax
      d_offset = ((d_max - d_min) / 2.0) + d_min
      e_offset = ((e_max - e_min) / 2.0) + e_min

      logger.info 'saving new d,e values'
      @lines = @input_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        if image
          image.d = (d_map[image.d] - d_offset).round(8).to_s
          image.e = (e_map[image.e] - e_offset).round(8).to_s
          image.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def fix_conversion_errors
      logger.info 'fixing conversion errors'
      @lines = @input_file.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp && cp.horizontal?
          cp.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def fix_unconnected_image_pairs
      logger.info 'fixing unconnected image pairs'
      panorama = Panorama.new(@input_file, logger)
      @lines = panorama.fix_unconnected_image_pairs_neighborhoods
      save_file
    end

    def generate_border_line_control_points
      logger.info 'generating border line control points'
      images = Image.parse(@input_file)
      line_control_points = ControlPoint.parse(@input_file, cp_type: :line)

      # Set vertical and horizontal control points for each image
      images.each do |image|
        vertical_control_points = line_control_points.select { |cp| cp[:n] == image[:id] && cp[:N] == image[:id] && cp[:t] == 1 }
        horizontal_control_points = line_control_points.select { |cp| cp[:n] == image[:id] && cp[:N] == image[:id] && cp[:t] == 2 }
        image[:vertical_control_points] = vertical_control_points
        image[:horizontal_control_points] = horizontal_control_points
      end

      # Iterate through the edges to create vertical control points across overlapping images
      logger.info 'finding common vertical control points'
      vertical_edges, horizontal_edges = images.map { |image| image[:d] }.minmax, images.map { |image| image[:e] }.minmax
      vertical_control_points = []
      vertical_edges.each do |edge|
        edge_images = images.select { |image| image[:d] == edge }.sort_by { |image| image[:e] }
        edge_images.each_with_index do |image, index|
          next if index == edge_images.length - 1
          next_image = edge_images[index+1]

          control_points = image[:vertical_control_points].map do |control_point|
            average_x = (control_point[:x] + control_point[:X]) / 2.0
            next_found_control_point = next_image[:vertical_control_points].find do |next_control_point|
              next_average_x = (next_control_point[:x] + next_control_point[:X]) / 2.0
              next_average_x.between?(average_x * 0.98, average_x * 1.02)
            end
            [control_point, next_found_control_point] if next_found_control_point
          end.compact

          # Special logic for anchor image
          if image[:id] == 0
            control_points = next_image[:vertical_control_points].map do |next_control_point|
              next_average_x = (next_control_point[:x] + next_control_point[:X]) / 2.0
              [{n: 0, x: next_average_x, y: (image[:h]/2.0).round }, next_control_point]
            end
          elsif next_image[:id] == 0
            control_points = image[:vertical_control_points].map do |next_control_point|
              next_average_x = (next_control_point[:x] + next_control_point[:X]) / 2.0
              [{n: 0, x: next_average_x, y: (image[:h]/2.0).round }, next_control_point]
            end
          end

          control_points.each do |current_control_point, next_control_point|
            vertical_control_points << ControlPoint.new({
                                                          n: current_control_point[:n],
                                                          N: next_control_point[:n],
                                                          x: current_control_point[:x],
                                                          y: current_control_point[:y],
                                                          X: next_control_point[:X],
                                                          Y: next_control_point[:Y],
                                                          t: 1
                                                        })
          end
        end
      end

      # Iterate through the edges to create horizontal control points across overlapping images
      logger.info 'finding common horizontal control points'
      horizontal_control_points = []
      horizontal_edges.each do |edge|
        edge_images = images.select { |image| image[:e] == edge }.sort_by { |image| image[:d] }
        edge_images.each_with_index do |image, index|
          next if index == edge_images.length - 1
          next_image = edge_images[index+1]

          control_points = image[:horizontal_control_points].map do |control_point|
            average_y = (control_point[:y] + control_point[:Y]) / 2.0
            next_found_control_point = next_image[:horizontal_control_points].find do |next_control_point|
              next_average_y = (next_control_point[:y] + next_control_point[:Y]) / 2.0
              next_average_y.between?(average_y * 0.98, average_y * 1.02)
            end
            [control_point, next_found_control_point] if next_found_control_point
          end.compact

          # Special logic for anchor image
          if image[:id] == 0
            control_points = next_image[:horizontal_control_points].map do |next_control_point|
              next_average_y = (next_control_point[:y] + next_control_point[:Y]) / 2.0
              [{n: 0, x: (image[:w]/2.0).round, y: next_average_y }, next_control_point]
            end
          end

          control_points.each do |current_control_point, next_control_point|
            horizontal_control_points << ControlPoint.new({
                                                            n: current_control_point[:n],
                                                            N: next_control_point[:n],
                                                            x: current_control_point[:x],
                                                            y: current_control_point[:y],
                                                            X: next_control_point[:X],
                                                            Y: next_control_point[:Y],
                                                            t: 2
                                                          })
          end
        end
      end

      logger.info "writing #{vertical_control_points.count} vertical control points"
      logger.info "writing #{horizontal_control_points.count} horizontal control points"
      control_point_lines_started = false
      @lines = @input_file.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp.nil?
          # Control point lines ended
          if control_point_lines_started
            control_point_lines_started = false
            (vertical_control_points + horizontal_control_points).map do |control_point|
              logger.debug "image #{control_point[:n]} <> #{control_point[:N]} #{control_point[:t] == 1 ? 'vertical' : 'horizontal'} control point"
              control_point.to_s
            end + [line]
          else
            next line
          end
        else
          control_point_lines_started = true
          next line
        end
      end.compact.flatten

      save_file
    end

    def get_detailed_control_point_info
      logger.info 'getting detailed control point info'
      images = Image.parse(@input_file)
      panorama_variable = PanoramaVariable.parse(@input_file).first
      ControlPoint.parse(@input_file)
      control_points = ControlPoint.calculate_distances(images, panorama_variable)

      control_points.each do |cp|
        logger.debug cp.detailed_info
      end
    end

    def merge_image_parameters
      logger.info 'merging image parameters'
      control_points = ControlPoint.parse(@compare_file)
      v_lines_started = false
      @lines = @input_file.each_line.map do |line|
        if line[0] == 'v'
          v_lines_started = true
          next line
        elsif v_lines_started
          v_lines_started = false
          control_points.map(&:to_s).join
        else
          next line
        end
      end.compact

      save_file
    end

    def optimize
      logger.info 'optimizing'
      panorama = Panorama.new(@input_file, logger)
      optimizer = Optimizer.new(panorama)
      optimizer.run

      @lines = @input_file.each_line.map do |line|
        image = optimizer.images.find { |i| i.raw == line }
        if image
          image.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def prepare_for_pr0ntools
      logger.info 'preparing for pr0ntools'

      images = Image.parse(@input_file)
      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort
      fov = images.map(&:v).uniq.find { |v| v != 0.0 }
      images.each do |i|
        i[:original_n] = i.n
        i.n = "c#{ds.reverse.index(i.d)}_r#{es.reverse.index(i.e)}.jpg"
        i.v = fov
      end
      images = images.sort_by(&:n)

      index = -1
      @lines = @input_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        next line unless image
        index += 1
        images[index].to_s
      end.compact

      dir = '/pr0ntools/'
      logger.info "creating #{dir}"
      new_dir = Pathname.new(@output).dirname.to_s + dir
      FileUtils.mkdir_p(new_dir)

      logger.info 'renaming files to format cX_rY.jpg'
      images.each { |image| FileUtils.cp(image[:original_n], new_dir + image.n) }

      logger.info 'creating scan.json'
      image_first_col = images.find { |image| image.n == 'c0_r0.jpg' }
      image_second_col = images.find { |image| image.n == 'c1_r0.jpg' }
      overlap = ((image_second_col.d - image_first_col.d).abs / image_first_col.w.to_f).round(4)
      File.open(new_dir+'scan.json', 'w') { |f| f.puts %Q({"overlap":#{overlap}}) }

      save_file(dir: dir)
    end

    def remove_anchor_variables
      logger.info 'removing anchor variables'
      variables = OptimisationVariable.parse(@input_file)

      @lines = @input_file.each_line.map do |line|
        variable = variables.find { |v| v.raw == line }
        if variable && (variable.d == 0 || variable.e == 0)
          next
        else
          next line
        end
      end.compact

      save_file
    end

    def standardize_roll
      logger.info 'standardizing roll'
      images = Image.parse(@input_file)
      panorama_variable = PanoramaVariable.parse(@input_file).first
      ControlPoint.parse(@input_file)
      control_points = ControlPoint.calculate_distances(images, panorama_variable)
      max_count = (images.count * 0.5).ceil - 1
      pairs = control_points.group_by { |cp| [cp.n1, cp.n2] }.sort_by { |_, members| -members.count }[0..max_count]
      image_ids = pairs.map { |image_ids, _| image_ids }.flatten.uniq
      rolls = images.select { |image| image_ids.include?(image.id) }.map(&:r)

      average_roll, roll_std = *calculate_average_and_std(name: :roll, values: rolls, logger: logger)
      new_rolls = rolls.select { |r| (r - average_roll).abs < roll_std }
      logger.info "removed #{rolls.count - new_rolls.count} outliers"
      average_roll, _ = *calculate_average_and_std(name: :roll, values: new_rolls, logger: logger)
      logger.info "converting all rolls to #{average_roll}"

      @lines = @input_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        if image
          image.r = average_roll
          image.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    private

    def save_file(dir: nil)
      logger.info 'saving file'
      if dir
        new_dir = Pathname.new(@output).dirname.to_s + dir
        FileUtils.mkdir_p(new_dir)
        @output = new_dir + Pathname.new(@output).basename.to_s
        @output_file = File.new(@output, 'w')
      end

      @lines.each do |good_line|
        @output_file.write good_line
      end

      @output_file.close
    end
  end
end
