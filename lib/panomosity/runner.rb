module Panomosity
  class Runner
    AVAILABLE_COMMANDS = %w(
    check_position_changes
    convert_equaled_image_parameters
    convert_horizontal_lines
    convert_translation_parameters
    crop_centers
    fix_conversion_errors
    generate_border_line_control_points
    merge_image_parameters
    prepare_for_pr0ntools
    remove_long_lines
    remove_anchor_variables
    standardize_roll
  )

    ########
    # Open files
    def initialize(input_pto_file_path: nil, output_pto_file_path: nil, check_pto_file_path: nil)
      @input_pto_file_path = input_pto_file_path
      @output_pto_file_path = output_pto_file_path
      @check_pto_file_path = check_pto_file_path
      @input_pto_file = File.new(@input_pto_file_path, 'r').read rescue puts('You must have at least one argument')
      @output_pto_file = File.new(@output_pto_file_path, 'w') if @output_pto_file_path
      @check_pto_file = File.new(@check_pto_file_path, 'r').read if @check_pto_file_path
      options = {}
      OptionParser.new do |opts|
        opts.banner = 'Usage: example.rb [options]'

        opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
          options[:verbose] = v
        end
      end.parse!
    end

    def run(command)
      if AVAILABLE_COMMANDS.include?(command)
        send(command)
      else
        show_help
      end
    end

    def convert_horizontal_lines
      @lines = @input_pto_file.each_line.map do |line|
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

    def fix_conversion_errors
      @lines = @input_pto_file.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp && cp.horizontal?
          cp.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def generate_border_line_control_points
      images = Image.parse(@input_pto_file)
      line_control_points = ControlPoint.parse(@input_pto_file, cp_type: :line)

      # Set vertical and horizontal control points for each image
      images.each do |image|
        vertical_control_points = line_control_points.select { |cp| cp[:n] == image[:id] && cp[:N] == image[:id] && cp[:t] == 1 }
        horizontal_control_points = line_control_points.select { |cp| cp[:n] == image[:id] && cp[:N] == image[:id] && cp[:t] == 2 }
        image[:vertical_control_points] = vertical_control_points
        image[:horizontal_control_points] = horizontal_control_points
      end

      # Iterate through the edges to create vertical control points across overlapping images
      vertical_edges, horizontal_edges = images.map { |image| image[:d] }.minmax, images.map { |image| image[:e] }.minmax
      vertical_control_points = []
      vertical_edges.each do |edge|
        # p "vertical edge #{edge}"
        edge_images = images.select { |image| image[:d] == edge }.sort_by { |image| image[:e] }
        edge_images.each_with_index do |image, index|
          next if index == edge_images.length - 1
          next_image = edge_images[index+1]

          control_points = image[:vertical_control_points].map do |control_point|
            # p "current control point #{control_point}"
            average_x = (control_point[:x] + control_point[:X]) / 2.0
            next_found_control_point = next_image[:vertical_control_points].find do |next_control_point|
              next_average_x = (next_control_point[:x] + next_control_point[:X]) / 2.0
              # p "next control point #{next_control_point}"
              # p "average x #{average_x}"
              # p "next average x #{next_average_x}"

              next_average_x.between?(average_x * 0.98, average_x * 1.02)
            end
            [control_point, next_found_control_point] if next_found_control_point
          end.compact

          # Special logic for anchor image
          # p "on anchor"
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
      horizontal_control_points = []
      horizontal_edges.each do |edge|
        # p "horizontal edge #{edge}"
        edge_images = images.select { |image| image[:e] == edge }.sort_by { |image| image[:d] }
        edge_images.each_with_index do |image, index|
          next if index == edge_images.length - 1
          next_image = edge_images[index+1]

          control_points = image[:horizontal_control_points].map do |control_point|
            # p "current control point #{control_point}"
            average_y = (control_point[:y] + control_point[:Y]) / 2.0
            next_found_control_point = next_image[:horizontal_control_points].find do |next_control_point|
              next_average_y = (next_control_point[:y] + next_control_point[:Y]) / 2.0
              # p "next control point #{next_control_point}"
              # p "average y #{average_y}"
              # p "next average y #{next_average_y}"

              next_average_y.between?(average_y * 0.98, average_y * 1.02)
            end
            [control_point, next_found_control_point] if next_found_control_point
          end.compact

          # Special logic for anchor image
          # p "on anchor"
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

      puts "writing #{vertical_control_points.count} vertical control points"
      puts "writing #{horizontal_control_points.count} horizontal control points"
      control_point_lines_started = false
      @lines = @input_pto_file.each_line.map do |line|
        cp = ControlPoint.parse_line(line)
        if cp.nil?
          # Control point lines ended
          if control_point_lines_started
            control_point_lines_started = false
            (vertical_control_points + horizontal_control_points).map do |control_point|
              puts "image #{control_point[:n]} <> #{control_point[:N]} #{control_point[:t] == 1 ? 'vertical' : 'horizontal'} control point"
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

    def check_position_changes
      original_images = Image.parse(@input_pto_file)
      changed_images = Image.parse(@check_pto_file)
      threshold = 0.10
      images = original_images.zip(changed_images)
      changes_x = images.select do |original, changed|
        ratio_x = original.x / changed.x
        changed_x = (1 - ratio_x.abs).abs
        changed_x > threshold
      end
      changes_y = images.select do |original, changed|
        ratio_y = original.y / changed.y
        changed_y = (1 - ratio_y.abs).abs
        changed_y > threshold
      end

      @lines = @input_pto_file.each_line.map do |line|
        var_data = line.match /\Av\s(TrX|TrY)(\d+)\n?\z/
        _, position, image_id = *var_data.to_a
        next line unless image_id
        case position
          when 'TrX'
            if changes_x.find { |original, __| original.id.to_s == image_id }
              puts "Removing #{position}#{image_id}"
            else
              next line
            end
          when 'TrY'
            if changes_y.find { |original, __| original.id.to_s == image_id }
              puts "Removing #{position}#{image_id}"
            else
              next line
            end
          else
            next line
        end
      end

      save_file
    end

    def remove_long_lines
      images = Image.parse(@input_pto_file)
      control_points = ControlPoint.get_detailed_info(@input_pto_file_path, cp_type: :normal)
      control_points.each do |cp|
        image1 = images.find { |i| cp.n1 == i.id }
        image2 = images.find { |i| cp.n2 == i.id }
        # dist = ((image1.normal_x + cp.x1) - (image2.normal_x + cp.x2)) ** 2 + ((image1.normal_y + cp.y1) - (image2.normal_y + cp.y2)) ** 2
        dx = (image1.d - cp.x1) - (image2.d - cp.x2)
        dy = (image1.e - cp.y1) - (image2.e - cp.y2)
        puts "#{cp.to_s} distrt #{Math.sqrt(dx**2+dy**2)} iy1 #{image1.normal_y} iy2 #{image2.normal_y}"
      end
      puts "avg #{control_points.map(&:dist).reduce(:+)/control_points.count.to_f}"
    end

    def convert_translation_parameters
      images = Image.parse(@input_pto_file)

      @lines = @input_pto_file.each_line.map do |line|
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

    def prepare_for_pr0ntools
      puts 'Preparing for pr0ntools'

      images = Image.parse(@input_pto_file)
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
      @lines = @input_pto_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        next line unless image
        index += 1
        images[index].to_s
      end.compact

      dir = '/pr0ntools/'
      puts "creating #{dir}"
      new_dir = Pathname.new(@output_pto_file_path).dirname.to_s + dir
      FileUtils.mkdir_p(new_dir)

      puts 'renaming files to format cX_rY.jpg'
      images.each { |image| FileUtils.cp(image[:original_n], new_dir + image.n) }

      puts 'creating scan.json'
      image_first_col = images.find { |image| image.n == 'c0_r0.jpg' }
      image_second_col = images.find { |image| image.n == 'c1_r0.jpg' }
      overlap = ((image_second_col.d - image_first_col.d).abs / image_first_col.w.to_f).round(4)
      File.open(new_dir+'scan.json', 'w') { |f| f.puts %Q({"overlap":#{overlap}}) }

      save_file(dir: dir)
    end

    def merge_image_parameters
      control_points = ControlPoint.parse(@check_pto_file)
      v_lines_started = false
      @lines = @input_pto_file.each_line.map do |line|
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

    def convert_equaled_image_parameters
      puts 'converting equaled image parameters'
      images = Image.parse(@input_pto_file)
      @lines = @input_pto_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        if image
          image.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def standardize_roll
      puts 'standardizing roll'
      images = Image.parse(@input_pto_file)
      rolls = images.map(&:r)
      average_roll = rolls.reduce(:+).to_f / rolls.count
      puts "average roll: #{average_roll}"
      roll_std = Math.sqrt(rolls.map { |r| (r - average_roll) ** 2 }.reduce(:+) / (rolls.count - 1))
      puts "roll std: #{roll_std}"
      new_rolls = rolls.select { |r| (r - average_roll).abs < roll_std }
      puts "removed #{rolls.count - new_rolls.count} outliers"
      new_average_roll = new_rolls.reduce(:+).to_f / new_rolls.count
      puts "converting all rolls to #{new_average_roll}"

      @lines = @input_pto_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        if image
          image.r = new_average_roll
          image.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    # Uses image magick to crop centers
    def crop_centers
      images = Image.parse(@input_pto_file)
      images.each do |image|
        geometry = `identify -verbose #{image.name} | grep Geometry`.strip
        _, width, height = *geometry.match(/(\d{2,5})x(\d{2,5})(\+|\-)\d{1,5}(\+|\-)\d{1,5}/)
        puts "cropping #{image.name}"
        `convert #{image.name} -crop "50%x50%+#{(width.to_f/4).round}+#{(height.to_f/4).round}" #{image.name}`
      end
      # Since all images have been cropped, we need to change d,e params to move images based on how much was cropped
      # Re-run commands that have been run at this point

      puts 'Rerunning commands'
      @new_input_file_path = 'project_converted_translation_cropped.pto'
      `match-n-shift --input #{@check_pto_file_path} -o project_cropped.pto`
      `pto_var --opt=TrX,TrY project_cropped.pto -o project_pto_var_cropped.pto`
      `ruby pano.rb convert_translation_parameters project_pto_var_cropped.pto #{@new_input_file_path}`
      `pano_modify -p 0 --fov=AUTO -o #{@new_input_file_path} #{@new_input_file_path}`

      puts "Read new #{@new_input_file_path}"
      # Read new input pto file
      @input_pto_file = File.new(@new_input_file_path, 'r').read
      images = Image.parse(@input_pto_file)
      ds = images.map(&:d).uniq.sort
      es = images.map(&:e).uniq.sort

      d_diffs = []
      ds.each_with_index do |_, i|
        next if i == 0
        d_diffs.push((ds[i] - ds[i-1]).abs / 2)
      end

      e_diffs = []
      es.each_with_index do |_, i|
        next if i == 0
        e_diffs.push((es[i] - es[i-1]).abs / 2)
      end

      d_map = Hash[ds.map.with_index { |d, i| i == 0 ? [d, d] : [d, d - d_diffs[0..(i-1)].reduce(:+)] }]
      e_map = Hash[es.map.with_index { |e, i|  i == 0 ? [e, e] : [e, e - e_diffs[0..(i-1)].reduce(:+)] }]

      d_min, d_max = d_map.values.minmax
      e_min, e_max = e_map.values.minmax
      d_offset = ((d_max - d_min) / 2.0) + d_min
      e_offset = ((e_max - e_min) / 2.0) + e_min

      puts 'Saving new d,e values'
      @lines = @input_pto_file.each_line.map do |line|
        image = images.find { |i| i.raw == line }
        if image
          image.d = (d_map[image.d] - d_offset).round(8)
          image.e = (e_map[image.e] - e_offset).round(8)
          image.to_s
        else
          next line
        end
      end.compact

      save_file
    end

    def remove_anchor_variables
      puts 'removing anchor variables'
      variables = OptimizationVariable.parse(@input_pto_file)

      @lines = @input_pto_file.each_line.map do |line|
        variable = variables.find { |v| v.raw == line }
        if variable && (variable.d == 0 || variable.e == 0)
          next
        else
          next line
        end
      end.compact

      save_file
    end

    private

    def save_file(dir: nil)
      if dir
        new_dir = Pathname.new(@output_pto_file_path).dirname.to_s + dir
        FileUtils.mkdir_p(new_dir)
        @output_pto_file_path = new_dir + Pathname.new(@output_pto_file_path).basename.to_s
        @output_pto_file = File.new(@output_pto_file_path, 'w')
      end

      @lines.each do |good_line|
        @output_pto_file.write good_line
      end

      @output_pto_file.close
    end

    def show_help
      puts 'ruby pano.rb command input_filename output_filename check_filename(optional)'
      puts "commands include:\n #{AVAILABLE_COMMANDS.join("\n")}"
    end
  end
end
