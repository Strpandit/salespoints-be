require "prawn"
require "prawn/table"

module Reports
  module Formatters
    class PdfFormatter
      def self.render(report_data)
        pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [30, 30, 30, 30])

        pdf.fill_color "1E40AF"
        title_text = sanitize_text(report_data[:title] || "Marketplace Report").upcase
        pdf.text title_text, size: 14, style: :bold
        pdf.fill_color "4B5563"
        pdf.text "SALESPOINTS INDIA PVT LTD | Confidential Specification Report", size: 8
        pdf.text "Generated On: #{Time.current.strftime('%d %b %Y %H:%M IST')}", size: 8
        pdf.move_down 10

        table_data = []
        if report_data[:headers].present?
          table_data << report_data[:headers].map { |h| sanitize_text(h) }
        end

        (report_data[:rows] || []).each do |row|
          table_data << row.map { |cell| sanitize_text(cell) }
        end

        if table_data.present?
          pdf.table(table_data, header: true, width: pdf.bounds.width) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "1E40AF"
            t.row(0).text_color = "FFFFFF"
            t.row(0).align = :center
            t.cells.padding = 4
            t.cells.size = 7
            t.row_colors = ["FFFFFF", "F9FAFB"]
          end
        end

        pdf.number_pages "Page <page> of <total>", at: [pdf.bounds.right - 100, 0], align: :right, size: 8

        pdf.render
      end

      def self.sanitize_text(val)
        val.to_s.gsub("₹", "Rs. ").encode("Windows-1252", invalid: :replace, undef: :replace, replace: "")
      end
    end
  end
end
