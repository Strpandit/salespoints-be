require 'csv'
module Api
  class DealerBulkUploadsController < ApplicationController

    def create
      return render json: { error: 'Only dealers can bulk upload' }, status: :forbidden unless current_dealer

      file = params[:file]
      unless file && file.respond_to?(:read)
        return render json: { error: 'CSV file is required as `file` param' }, status: :bad_request
      end

      success = []
      errors = []

      CSV.parse(file.read, headers: true).each_with_index do |row, idx|
        begin
          # Expected columns: product_sku, variant_sku, dealer_price, dealer_selling_price, stock_quantity, modal_no
          product_sku = row['product_sku'] || row['sku']
          variant_sku = row['variant_sku'] || row['variant']

          product = Product.find_by(sku: product_sku)
          unless product
            errors << { row: idx + 1, error: "Product with sku=#{product_sku} not found" }
            next
          end

          variant = if variant_sku.present?
                      product.product_variants.find_by(variant_sku: variant_sku)
                    else
                      product.product_variants.first
                    end

          unless variant
            errors << { row: idx + 1, error: "Variant with sku=#{variant_sku} not found for product #{product_sku}" }
            next
          end

          dp = DealerProduct.find_or_initialize_by(dealer: current_dealer, product_variant: variant)
          dp.product = product
          dp.stock_quantity = row['stock_quantity'].to_i
          dp.dealer_selling_price = row['dealer_selling_price'] || row['dealer_price'] || variant.dealer_selling_price
          dp.dealer_price = row['dealer_price'] || variant.dealer_price
          dp.modal_no = row['modal_no'] if row['modal_no']
          dp.is_active = true
          dp.approve_status = 'approved'

          if dp.save
            success << { row: idx + 1, dealer_product_id: dp.id }
          else
            errors << { row: idx + 1, error: dp.errors.full_messages }
          end
        rescue => e
          errors << { row: idx + 1, error: e.message }
        end
      end

      render json: { success_count: success.size, errors_count: errors.size, successes: success, errors: errors }, status: :ok
    end
  end
end
