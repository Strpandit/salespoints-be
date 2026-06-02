class MarketplaceOrderFinancials
  class << self
    def build(total_amount:)
      total = BigDecimal(total_amount.to_s)
      commission_rate = commission_rate_percent
      extra_rate = extra_charge_rate_percent
      commission_amount = percentage_of(total, commission_rate)
      marketplace_fee_amount = percentage_of(total, extra_rate)
      seller_amount = total - commission_amount - marketplace_fee_amount

      {
        commission_rate: commission_rate,
        commission_amount: commission_amount.round(2),
        marketplace_fee_amount: marketplace_fee_amount.round(2),
        seller_settlement_amount: seller_amount.negative? ? 0.to_d : seller_amount.round(2),
        settlement_status: "on_hold",
        refund_status: "none",
        refund_amount: 0.to_d
      }
    end

    def return_window_days
      env_integer("ORDER_RETURN_WINDOW_DAYS", default: 7)
    end

    def settlement_hold_days
      env_integer("ORDER_SETTLEMENT_HOLD_DAYS", default: return_window_days)
    end

    private

    def commission_rate_percent
      decimal_env("MARKETPLACE_COMMISSION_PERCENT", default: "10")
    end

    def extra_charge_rate_percent
      decimal_env("MARKETPLACE_EXTRA_CHARGE_PERCENT", default: "0")
    end

    def percentage_of(amount, rate)
      return 0.to_d if amount <= 0 || rate <= 0

      (amount * rate / 100)
    end

    def decimal_env(key, default:)
      BigDecimal(ENV[key].presence || default)
    end

    def env_integer(key, default:)
      value = ENV[key].presence
      value.present? ? value.to_i : default
    end
  end
end
