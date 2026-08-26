module Reports
  class PrivacyFilter
    def self.buyer_reference(order, scope: :vendor)
      return "N/A" unless order

      if scope == :vendor
        if order.is_a?(B2bOrder)
          order.buyer_dealer&.dealer_code.presence || "Dealer"
        elsif order.is_a?(Order) && order.buyer_type == "Dealer"
          dealer = Dealer.find_by(id: order.buyer_id)
          dealer&.dealer_code.presence || "Dealer"
        else
          account = Account.find_by(id: order.buyer_id)
          name = account ? [account.first_name, account.last_name].compact.join(" ").strip : ""
          name.presence || "B2C Customer"
        end
      else
        if order.is_a?(B2bOrder)
          profile = order.buyer_dealer&.dealer_profile
          profile&.business_name.presence || order.buyer_dealer&.full_name.presence || order.buyer_dealer&.dealer_code.presence || "Dealer"
        elsif order.is_a?(Order) && order.buyer_type == "Account"
          account = Account.find_by(id: order.buyer_id)
          name = account ? [account.first_name, account.last_name].compact.join(" ").strip : ""
          contact = account&.phone.presence || account&.email.presence
          name.present? ? (contact ? "#{name} (#{contact})" : name) : (contact || "Customer")
        else
          dealer = Dealer.find_by(id: order.buyer_id)
          dealer ? "#{dealer.full_name} [#{dealer.dealer_code}]" : "Dealer"
        end
      end
    end

    def self.format_payment_method(method)
      m = method.to_s.strip.downcase
      if m == "cod" || m == "postpaid"
        "Postpaid"
      else
        "Prepaid"
      end
    end
  end
end
