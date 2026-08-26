require "caxlsx"

module Reports
  module Formatters
    class XlsxFormatter
      def self.render(report_data)
        p = Axlsx::Package.new
        wb = p.workbook

        wb.styles do |s|
          title_style  = s.add_style(b: true, sz: 14, fg_color: "1F2937")
          meta_style   = s.add_style(i: true, sz: 10, fg_color: "6B7280")
          header_style = s.add_style(b: true, bg_color: "1E40AF", fg_color: "FFFFFF", alignment: { horizontal: :center })
          row_style    = s.add_style(sz: 10)

          wb.add_worksheet(name: (report_data[:title] || "Report").first(31)) do |sheet|
            sheet.add_row [report_data[:title] || "Salespoints Marketplace Report"], style: title_style
            sheet.add_row ["Generated: #{Time.current.strftime('%d %b %Y %H:%M IST')}"], style: meta_style
            sheet.add_row []

            if report_data[:headers].present?
              sheet.add_row report_data[:headers], style: header_style
            end

            (report_data[:rows] || []).each do |row|
              sheet.add_row row, style: row_style
            end
          end
        end

        p.to_stream.read
      end
    end
  end
end
