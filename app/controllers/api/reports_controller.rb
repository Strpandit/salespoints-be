module Api
  class ReportsController < ApplicationController
    before_action :authorize_reports_access

    # GET /api/reports/list
    def list
      data = if current_user_type == "AdminUser"
        [
          # Sales (8)
          { key: "sales_summary",        name: "Sales Summary Report",         group: "Sales",                formats: ["xlsx", "pdf"] },
          { key: "sales_detailed",       name: "Detailed Sales Register",      group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "b2c_sales",            name: "B2C Sales Register",           group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "b2b_sales",            name: "B2B Sales Register",           group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "wholesale_sales",      name: "Wholesale Sales Register",     group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "product_wise_sales",   name: "Product-wise Sales",           group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "category_brand_sales", name: "Category & Brand Sales",       group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "state_region_sales",   name: "State / Region Sales",         group: "Sales",                formats: ["xlsx", "csv"] },

          # Orders (4)
          { key: "all_orders",           name: "All Orders Status Tracker",    group: "Orders",               formats: ["xlsx", "csv"] },
          { key: "completed_orders",     name: "Completed Orders Register",    group: "Orders",               formats: ["xlsx", "csv"] },
          { key: "cancelled_orders",     name: "Cancelled Orders Register",    group: "Orders",               formats: ["xlsx", "csv"] },
          { key: "pending_failed_orders",name: "Pending / Failed Orders",      group: "Orders",               formats: ["xlsx", "csv"] },

          # Revenue (5)
          { key: "revenue_summary",      name: "Revenue Summary Report",       group: "Revenue",              formats: ["xlsx", "pdf"] },
          { key: "product_revenue",      name: "Product Revenue Report",       group: "Revenue",              formats: ["xlsx", "csv"] },
          { key: "vendor_revenue",       name: "Vendor Revenue Report",        group: "Revenue",              formats: ["xlsx", "csv"] },
          { key: "gross_margin",         name: "Gross Margin Report",          group: "Revenue",              formats: ["xlsx", "pdf"] },
          { key: "profitability",        name: "Contribution Margin Report",   group: "Revenue",              formats: ["xlsx", "pdf"] },

          # Purchases/Vendors (6)
          { key: "dealer_purchase",      name: "Dealer Purchase Register",     group: "Purchases & Vendors",  formats: ["xlsx", "csv"] },
          { key: "vendor_invoice",       name: "Vendor Invoice Register",      group: "Purchases & Vendors",  formats: ["xlsx", "csv"] },
          { key: "vendor_wise_purchases",name: "Vendor-wise Purchase Volume",  group: "Purchases & Vendors",  formats: ["xlsx", "csv"] },
          { key: "vendor_payable",       name: "Vendor Payable Summary",       group: "Purchases & Vendors",  formats: ["xlsx", "pdf"] },
          { key: "vendor_ledger",        name: "Vendor Ledger Running Statement", group: "Purchases & Vendors",formats: ["xlsx", "pdf"] },
          { key: "vendor_payout",        name: "Vendor Payout Transfer Log",   group: "Purchases & Vendors",  formats: ["xlsx", "csv"] },

          # GST & Accounting (5)
          { key: "sales_gst",            name: "Sales GST Register (GSTR-1)",  group: "GST & Accounting",     formats: ["xlsx", "csv", "json"] },
          { key: "hsn_sales_summary",    name: "HSN Sales Tax Summary",        group: "GST & Accounting",     formats: ["xlsx", "csv", "json"] },
          { key: "credit_notes",         name: "Credit Note Register",         group: "GST & Accounting",     formats: ["xlsx", "csv"] },
          { key: "debit_notes",          name: "Debit Note Register",          group: "GST & Accounting",     formats: ["xlsx", "csv"] },
          { key: "gst_reconciliation",   name: "GST Reconciliation Statement", group: "GST & Accounting",     formats: ["xlsx", "pdf"] },

          # Payments (5)
          { key: "customer_payments",    name: "Customer Payment Transactions",group: "Payments",             formats: ["xlsx", "csv"] },
          { key: "prepaid_cod",          name: "Prepaid vs Postpaid Register", group: "Payments",             formats: ["xlsx", "csv", "pdf"] },
          { key: "gateway_settlement",   name: "Payment Gateway Settlements",  group: "Payments",             formats: ["xlsx", "csv"] },
          { key: "payment_reconciliation",name: "Payment Reconciliation Log",  group: "Payments",             formats: ["xlsx", "csv"] },
          { key: "cod_reconciliation",   name: "COD Collections Reconciliation", group: "Payments",          formats: ["xlsx", "csv"] },

          # Inventory (4)
          { key: "stock_summary",        name: "Stock Summary Snapshot",       group: "Inventory",            formats: ["xlsx", "csv"] },
          { key: "stock_movement",       name: "Stock Movement Audit Ledger",  group: "Inventory",            formats: ["xlsx", "csv"] },
          { key: "low_stock",            name: "Low Stock Alert Report",       group: "Inventory",            formats: ["xlsx", "csv"] },
          { key: "inventory_aging",      name: "Inventory Aging Analysis",     group: "Inventory",            formats: ["xlsx", "pdf"] },

          # Analytics & Audit (3)
          { key: "vendor_performance",   name: "Vendor Performance & SLA",     group: "Analytics & Audit",    formats: ["xlsx", "pdf"] },
          { key: "customer_analytics",   name: "Customer LTV & Repeat Rates",  group: "Analytics & Audit",    formats: ["xlsx", "pdf"] },
          { key: "audit_trail",          name: "Audit Trail & Adjustments Log",group: "Analytics & Audit",    formats: ["xlsx", "pdf"] }
        ]
      else
        [
          { key: "sales_summary",       name: "Sales Summary Report",         group: "Sales",                formats: ["xlsx", "pdf"] },
          { key: "sales_detailed",      name: "Detailed Sales Report",        group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "b2c_sales",           name: "B2C Sales Report",             group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "b2b_sales",           name: "B2B Sales Report",             group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "wholesale_sales",     name: "Wholesale Sales Report",       group: "Sales",                formats: ["xlsx", "csv"] },
          { key: "order_report",        name: "Order Status Log",             group: "Sales",                formats: ["xlsx", "csv"] },

          { key: "revenue",             name: "Revenue Statement",            group: "Revenue",              formats: ["xlsx", "pdf"] },
          { key: "product_revenue",     name: "Product Revenue Breakup",      group: "Revenue",              formats: ["xlsx", "csv"] },
          { key: "category_revenue",    name: "Category Sales Distribution",  group: "Revenue",              formats: ["xlsx"] },

          { key: "hsn_summary",         name: "HSN Tax Summary",              group: "Invoices & GST",       formats: ["xlsx"] },

          { key: "prepaid_cod_sales",   name: "Prepaid vs Postpaid Sales",    group: "Payments",             formats: ["xlsx", "csv"] },
          { key: "payout_summary",      name: "Payout Cycle Summary",         group: "Payments",             formats: ["xlsx", "pdf"] },
          { key: "payout_details",      name: "Order-level Payout Breakup",   group: "Payments",             formats: ["xlsx", "csv"] },
          { key: "vendor_ledger",       name: "Vendor Ledger Statement",      group: "Payments",             formats: ["xlsx", "pdf"] },
          { key: "outstanding_payment", name: "Outstanding Payments Receivable", group: "Payments",         formats: ["xlsx", "pdf"] },

          { key: "replacements",        name: "Replacements & Returns Log",   group: "Replacements",         formats: ["xlsx", "csv"] },
          { key: "stock_report",        name: "Current SKU Stock Report",     group: "Inventory & Performance", formats: ["xlsx", "csv"] },
          { key: "product_performance", name: "Product Performance & Velocity", group: "Inventory & Performance", formats: ["xlsx", "pdf"] }
        ]
      end
      render json: { success: true, data: data }
    end

    # POST /api/reports/generate
    def generate
      report_key = params[:report_key].presence || params[:report_type].presence || "sales_summary"
      format     = (params[:format].presence || "xlsx").to_s.downcase
      filters    = params[:filters] || params.slice(:period, :start_date, :end_date)

      scope = current_user_type == "AdminUser" ? :admin : :vendor
      user  = scope == :admin ? current_admin_user : current_dealer

      exporter    = Reports::ExporterFactory.for(report_key, filters: filters, current_user: user, scope: scope)
      report_data = exporter.generate

      formatted_data = case format
                       when "xlsx" then Reports::Formatters::XlsxFormatter.render(report_data)
                       when "pdf"  then Reports::Formatters::PdfFormatter.render(report_data)
                       when "json" then Reports::Formatters::JsonFormatter.render(report_data)
                       else             Reports::Formatters::CsvFormatter.render(report_data)
                       end

      # Log download audit metadata (No files stored in DB/Cloud)
      ReportAuditLog.create!(
        user: user,
        report_key: report_key,
        format: format,
        applied_filters: filters.to_h,
        row_count: (report_data[:rows] || []).size,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        downloaded_at: Time.current
      )

      mime_type = case format
                  when "xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                  when "pdf"  then "application/pdf"
                  when "json" then "application/json"
                  else             "text/csv; charset=utf-8"
                  end

      send_data(
        formatted_data,
        filename: "#{report_key}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.#{format}",
        type: mime_type,
        disposition: "attachment"
      )
    end

    private

    def authorize_reports_access
      return if current_user_type.in?(%w[AdminUser Dealer])
      render json: { success: false, error: "Access denied" }, status: :forbidden
    end
  end
end
