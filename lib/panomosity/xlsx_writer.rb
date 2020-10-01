require 'write_xlsx'

module Panomosity
  module XLSXWriter
    SEPERATE_CSV_COLUMNS = /,(?![^\[]*\])/.freeze


    def csv_to_xlsx(input_files, output_file)
      input_files = Array(input_files)

      logger.info "Creating #{output_file}.xlsx"

      workbook = WriteXLSX.new("#{output_file}.xlsx")

      input_files.each do |csv|
        logger.info "Creating #{csv} Worksheet"

        worksheet = workbook.add_worksheet(csv)

        seperate_csv_columns = /,(?![^\[]*\])/

        File.open(csv, "r") do |f|
          f.each_line do |rows|
            cells = rows.split(SEPERATE_CSV_COLUMNS)

            cells.each_with_index do |cell, column|
              row = f.lineno - 1
              data = cell.tr_s('"', '').strip
              worksheet.write(row, column, data)
            end
          end
        end
      end

      workbook.close

      logger.info "Done. Check for #{output_file}.xlsx"
    end
  end
end
