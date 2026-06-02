require "csv"
module Api
  class ReportsController < ApplicationController
    before_action :authorize_reports_access

    def generate
      report_type = params[:report_type].presence
      return render json: { success: false, error: "Invalid report type" }, status: :bad_request unless valid_report_type?(report_type)

      period = params[:period].presence || "monthly"
      format = params[:format].presence || "csv"
      orders = scoped_orders(date_range_for(period)).order(created_at: :desc)
      filename = "#{report_type}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.#{format}"
      file_path = Rails.root.join("tmp", filename)

      CSV.open(file_path, "w") do |csv|
        csv << ["Report Type", report_type]
        csv << ["Period", period]
        csv << ["Generated At", Time.current.iso8601]
        csv << []
        csv << ["Order Number", "Buyer Type", "Amount", "Payment Status", "Status", "Created At"]
        orders.find_each do |order|
          csv << [order.order_number, order.buyer_type, order.total_amount, order.payment_status, order.status, order.created_at]
        end
      end

      render json: {
        success: true,
        data: {
          filename: filename,
          download_url: "/api/reports/download/#{filename}"
        },
        message: "Report generated successfully"
      }
    end

    def download
      filename = params[:filename]
      file_path = Rails.root.join("tmp", filename)
      return render json: { success: false, error: "Report file not found" }, status: :not_found unless File.exist?(file_path)

      send_file file_path, filename: filename, type: "text/csv", disposition: "attachment"
    end

    def list
      data = if current_user_type == "AdminUser"
        [
          { type: "monthly_sales", name: "Monthly Sales Report", description: "Sales, payments, and order movement." },
          { type: "seller_payout", name: "Seller Payout Report", description: "Dealer payout and pending release summary." },
          { type: "commission", name: "Commission Report", description: "Marketplace commission and fee performance." }
        ]
      else
        [
          { type: "monthly_sales", name: "My Sales Report", description: "Your sales and order performance." },
          { type: "seller_payout", name: "My Payout Report", description: "Your pending and completed payout history." },
          { type: "commission", name: "My Commission Report", description: "Commission and settlement summary for your catalog." }
        ]
      end

      render json: { success: true, data: data }
    end

    def schedule
      render json: { success: true, message: "Scheduled reports are not configured yet." }
    end

    private

    def authorize_reports_access
      return if current_user_type.in?(%w[AdminUser Dealer])

      render json: { success: false, error: "Access denied" }, status: :forbidden
    end

    def valid_report_type?(report_type)
      %w[monthly_sales seller_payout commission].include?(report_type.to_s)
    end

    def scoped_orders(date_range)
      scope = Order.where(created_at: date_range)
      scope = scope.where(seller_dealer_id: current_dealer.id) if current_user_type == "Dealer"
      scope
    end

    def date_range_for(period)
      case period
      when "weekly"
        1.week.ago.beginning_of_day..Time.current.end_of_day
      when "quarterly"
        3.months.ago.beginning_of_day..Time.current.end_of_day
      when "yearly"
        1.year.ago.beginning_of_day..Time.current.end_of_day
      else
        1.month.ago.beginning_of_day..Time.current.end_of_day
      end
    end
  end
end
