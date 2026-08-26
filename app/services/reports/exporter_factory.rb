module Reports
  class ExporterFactory
    VENDOR_EXPORTERS = {
      "sales_summary"       => Reports::Vendor::SalesSummaryExporter,
      "sales_detailed"      => Reports::Vendor::DetailedSalesExporter,
      "b2c_sales"           => Reports::Vendor::B2cSalesExporter,
      "b2b_sales"           => Reports::Vendor::B2bSalesExporter,
      "wholesale_sales"     => Reports::Vendor::WholesaleSalesExporter,
      "prepaid_cod_sales"   => Reports::Vendor::PrepaidCodSalesExporter,
      "order_report"        => Reports::Vendor::OrderExporter,
      "revenue"             => Reports::Vendor::RevenueExporter,
      "product_revenue"     => Reports::Vendor::ProductRevenueExporter,
      "category_revenue"    => Reports::Vendor::CategoryRevenueExporter,
      "hsn_summary"         => Reports::Vendor::HsnSummaryExporter,
      "payout_summary"      => Reports::Vendor::PayoutSummaryExporter,
      "payout_details"      => Reports::Vendor::PayoutDetailsExporter,
      "vendor_ledger"       => Reports::Vendor::VendorLedgerExporter,
      "outstanding_payment" => Reports::Vendor::OutstandingPaymentExporter,
      "replacements"        => Reports::Vendor::ReplacementsExporter,
      "stock_report"        => Reports::Vendor::StockReportExporter,
      "product_performance" => Reports::Vendor::ProductPerformanceExporter
    }.freeze

    ADMIN_EXPORTERS = {
      "sales_summary"        => Reports::Admin::SalesSummaryExporter,
      "sales_detailed"       => Reports::Admin::DetailedSalesRegisterExporter,
      "b2c_sales"            => Reports::Admin::B2cSalesExporter,
      "b2b_sales"            => Reports::Admin::B2bSalesExporter,
      "wholesale_sales"      => Reports::Admin::WholesaleSalesExporter,
      "product_wise_sales"   => Reports::Admin::ProductWiseSalesExporter,
      "category_brand_sales" => Reports::Admin::CategoryBrandSalesExporter,
      "state_region_sales"   => Reports::Admin::StateRegionSalesExporter,
      "all_orders"           => Reports::Admin::AllOrdersExporter,
      "completed_orders"     => Reports::Admin::CompletedOrdersExporter,
      "cancelled_orders"     => Reports::Admin::CancelledOrdersExporter,
      "pending_failed_orders"=> Reports::Admin::PendingFailedOrdersExporter,
      "revenue_summary"      => Reports::Admin::RevenueSummaryExporter,
      "product_revenue"      => Reports::Admin::ProductRevenueExporter,
      "vendor_revenue"       => Reports::Admin::VendorRevenueExporter,
      "gross_margin"         => Reports::Admin::GrossMarginExporter,
      "profitability"        => Reports::Admin::ProfitabilityExporter,
      "dealer_purchase"      => Reports::Admin::DealerPurchaseRegisterExporter,
      "vendor_invoice"       => Reports::Admin::VendorInvoiceRegisterExporter,
      "vendor_wise_purchases" => Reports::Admin::VendorWisePurchasesExporter,
      "vendor_payable"       => Reports::Admin::VendorPayableSummaryExporter,
      "vendor_ledger"        => Reports::Admin::VendorLedgerExporter,
      "vendor_payout"        => Reports::Admin::VendorPayoutReportExporter,
      "sales_gst"            => Reports::Admin::SalesGstRegisterExporter,
      "hsn_sales_summary"    => Reports::Admin::HsnSalesSummaryExporter,
      "credit_notes"         => Reports::Admin::CreditNoteRegisterExporter,
      "debit_notes"          => Reports::Admin::DebitNoteRegisterExporter,
      "gst_reconciliation"   => Reports::Admin::GstReconciliationExporter,
      "customer_payments"    => Reports::Admin::CustomerPaymentTransactionsExporter,
      "prepaid_cod"          => Reports::Admin::PrepaidCodRegisterExporter,
      "gateway_settlement"   => Reports::Admin::GatewaySettlementExporter,
      "payment_reconciliation"=> Reports::Admin::PaymentReconciliationExporter,
      "cod_reconciliation"   => Reports::Admin::CodReconciliationExporter,
      "stock_summary"        => Reports::Admin::StockSummaryExporter,
      "stock_movement"       => Reports::Admin::StockMovementLedgerExporter,
      "low_stock"            => Reports::Admin::LowStockExporter,
      "inventory_aging"      => Reports::Admin::InventoryAgingExporter,
      "vendor_performance"   => Reports::Admin::VendorPerformanceExporter,
      "customer_analytics"   => Reports::Admin::CustomerAnalyticsExporter,
      "audit_trail"          => Reports::Admin::AuditTrailExporter
    }.freeze

    def self.for(report_key, filters: {}, current_user: nil, scope: :vendor)
      klass = if scope == :admin
        ADMIN_EXPORTERS[report_key.to_s] || Reports::Admin::SalesSummaryExporter
      else
        VENDOR_EXPORTERS[report_key.to_s] || Reports::Vendor::SalesSummaryExporter
      end

      klass.new(filters: filters, current_user: current_user, scope: scope)
    end
  end
end
