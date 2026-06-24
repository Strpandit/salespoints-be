module Pricing
  class PriceCalculator
    attr_reader :variant, :product, :quantity, :user_type, :discount_amount

    def initialize(variant:, quantity: 1, user_type: :dealer, discount_amount: 0)
      @variant = variant
      @Product = variant.product
      @quantity = quantity.to_i.positive? ? quantity.to_i : 1
      @user_type = user_type.to_sym
      @discount_amount = discount_amount.to_d
    end

    def call
      {
        unit_price: unit_price,
        quantity: quantity,
        subtotal: subtotal,
        taxable_amount: taxable_amount,
        gst_percentage: gst_percentage,
        gst_amount: gst_amount,
        discount_amount: discount_amount,
        total: total
      }
    end

    private

    def unit_price
      @unit_price ||= begin
        price =
          if user_type == :dealer
            variant.dealer_selling_price.presence ||
              variant.selling_price.presence ||
              variant.price.presence ||
              product.dealer_selling_price.presence ||
              product.selling_price.presence ||
              product.price.presence
          else
            variant.selling_price.presence ||
              variant.price.presence ||
              product.selling_price.presence ||
              product.price.presence
          end

        price.to_d
      end
    end

    def subtotal
      @subtotal ||= (unit_price * quantity).round(2)
    end

    def gst_percentage
      @gst_percentage ||= product&.tax_rate.to_d
    end

    # Inclusive GST
    def gst_amount
      @gst_amount ||= begin
        return 0.to_d if gst_percentage.zero?
       (subtotal - (subtotal / (1 + gst_percentage / 100.0))).round(2)
    end

    def taxable_amount
      @taxable_amount ||= (subtotal - gst_amount).round(2)
    end

    def total
      @total ||= (subtotal - discount_amount).round(2)
    end
  end
end
