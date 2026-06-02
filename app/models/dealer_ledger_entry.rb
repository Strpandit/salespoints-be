class DealerLedgerEntry < ApplicationRecord
  ENTRY_TYPES = %w[order_settlement refund_adjustment manual_adjustment payout_disbursement].freeze
  DIRECTIONS = %w[credit debit].freeze

  belongs_to :dealer
  belongs_to :order, optional: true
  belongs_to :return_request, optional: true

  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :amount, :balance_after, numericality: true
  validates :reference_code, uniqueness: true, allow_blank: true
end
