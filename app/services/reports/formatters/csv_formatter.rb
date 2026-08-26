require "csv"

module Reports
  module Formatters
    class CsvFormatter
      def self.render(report_data)
        CSV.generate(headers: true) do |csv|
          if report_data[:title].present?
            csv << ["Report", report_data[:title]]
            csv << ["Generated At", Time.current.strftime("%d %b %Y %H:%M:%S IST")]
            csv << []
          end

          csv << report_data[:headers] if report_data[:headers].present?
          (report_data[:rows] || []).each do |row|
            csv << row
          end
        end
      end
    end
  end
end
