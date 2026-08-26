module Reports
  module Admin
    class AuditTrailExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Log ID", "User Type", "User ID", "Report Key", "Format", "Rows Exported", "IP Address", "Downloaded At"]
        rows = ReportAuditLog.where(created_at: range).order(created_at: :desc).map do |al|
          [al.id, al.user_type, al.user_id, al.report_key, al.format.upcase, al.row_count, al.ip_address || "N/A", al.downloaded_at.strftime("%d %b %Y %H:%M:%S")]
        end

        { title: "Admin System Audit Trail & Report Download Log", headers: headers, rows: rows }
      end
    end
  end
end
