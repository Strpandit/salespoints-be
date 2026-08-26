module Reports
  module Formatters
    class JsonFormatter
      def self.render(report_data)
        {
          success: true,
          report: report_data[:title],
          generated_at: Time.current.iso8601,
          headers: report_data[:headers],
          total_rows: (report_data[:rows] || []).size,
          data: report_data[:rows]
        }.to_json
      end
    end
  end
end
