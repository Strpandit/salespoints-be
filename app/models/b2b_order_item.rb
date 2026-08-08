class B2bOrderItem < ApplicationRecord
  belongs_to :b2b_order
  belongs_to :dealer_product, optional: true
  belongs_to :product_variant, optional: true
  belongs_to :wholesaler_post, optional: true
  belongs_to :product_variant_color, optional: true

  STATUSES = %w[open accepted cancelled].freeze

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :total_price, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :open_items, -> { where(status: "open") }
  scope :accepted_items, -> { where(status: "accepted") }

  def accepted?
    status == "accepted"
  end

  def product_name_with_variant
    base = product_variant&.product&.name
    sku = product_variant&.variant_sku
    color_name = product_variant_color&.color_name || ad_hoc_color

    name_parts = [base]
    name_parts << "(#{sku})" if sku.present?
    name_parts << "- #{color_name}" if color_name.present?

    name_parts.compact.join(" ")
  end
end
