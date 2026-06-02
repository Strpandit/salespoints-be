class DealerLedgerService
  class << self
    def credit!(dealer:, amount:, entry_type:, description:, order: nil, return_request: nil, metadata: {})
      create_entry!(
        dealer: dealer,
        amount: amount,
        direction: "credit",
        entry_type: entry_type,
        description: description,
        order: order,
        return_request: return_request,
        metadata: metadata
      )
    end

    def debit!(dealer:, amount:, entry_type:, description:, order: nil, return_request: nil, metadata: {})
      create_entry!(
        dealer: dealer,
        amount: amount,
        direction: "debit",
        entry_type: entry_type,
        description: description,
        order: order,
        return_request: return_request,
        metadata: metadata
      )
    end

    private

    def create_entry!(dealer:, amount:, direction:, entry_type:, description:, order:, return_request:, metadata:)
      value = BigDecimal(amount.to_s).round(2)
      return if value <= 0

      Dealer.transaction do
        locked_dealer = Dealer.lock.find(dealer.id)
        next_balance =
          if direction == "credit"
            locked_dealer.settlement_balance.to_d + value
          else
            locked_dealer.settlement_balance.to_d - value
          end

        locked_dealer.update!(settlement_balance: next_balance.round(2))

        DealerLedgerEntry.create!(
          dealer: locked_dealer,
          order: order,
          return_request: return_request,
          entry_type: entry_type,
          direction: direction,
          amount: value,
          balance_after: next_balance.round(2),
          reference_code: build_reference(entry_type),
          description: description,
          metadata: metadata
        )
      end
    end

    def build_reference(entry_type)
      "#{entry_type.to_s.first(4).upcase}-#{SecureRandom.hex(6).upcase}"
    end
  end
end
