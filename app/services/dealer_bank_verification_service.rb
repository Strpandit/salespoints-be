class DealerBankVerificationService
  CACHE_PREFIX = "dealer_bank_verification".freeze
  CACHE_TTL = 30.minutes

  VerificationResult = Struct.new(
    :verification_reference,
    :cashfree_reference_id,
    :status,
    :bank_name,
    :name_at_bank,
    :account_number,
    :ifsc_code,
    :account_holder_name,
    :bank_payload,
    :ifsc_payload,
    keyword_init: true
  )

  def initialize(dealer:)
    @dealer = dealer
    @cashfree = CashfreeService.new
  end

  def verify!(account_number:, confirm_account_number:, account_holder_name:, ifsc_code:)
    normalized_account_number = account_number.to_s.gsub(/\s+/, "")
    normalized_confirm_account = confirm_account_number.to_s.gsub(/\s+/, "")
    normalized_ifsc = ifsc_code.to_s.strip.upcase
    normalized_holder_name = account_holder_name.to_s.squish

    raise StandardError, "Account number is required" if normalized_account_number.blank?
    raise StandardError, "Confirm account number is required" if normalized_confirm_account.blank?
    raise StandardError, "Account numbers do not match" unless normalized_account_number == normalized_confirm_account
    raise StandardError, "Account holder name is required" if normalized_holder_name.blank?
    raise StandardError, "IFSC code is required" if normalized_ifsc.blank?
    raise StandardError, "Cashfree is not configured" unless @cashfree.configured?

    ifsc_payload = @cashfree.verify_ifsc(ifsc_code: normalized_ifsc)
    bank_name = extract_bank_name(ifsc_payload)
    raise StandardError, "Unable to validate IFSC code" if bank_name.blank?

    verification_reference = "BANKVERIFY-#{@dealer.id}-#{SecureRandom.hex(6).upcase}"
    bank_payload = @cashfree.verify_bank_account(
      account_holder_name: normalized_holder_name,
      phone: @dealer.phone,
      bank_account: normalized_account_number,
      ifsc_code: normalized_ifsc,
      reference_id: verification_reference
    )

    cashfree_reference_id = bank_payload["reference_id"]

    account_status = bank_payload["account_status"].to_s.upcase
    account_status_code = bank_payload["account_status_code"].to_s.upcase

    if account_status == "RECEIVED" &&
     account_status_code == "VALIDATION_IN_PROGRESS"

      result = VerificationResult.new(
        verification_reference: verification_reference,
        cashfree_reference_id: cashfree_reference_id,
        status: "pending",
        bank_name: bank_name,
        name_at_bank: nil,
        account_number: normalized_account_number,
        ifsc_code: normalized_ifsc,
        account_holder_name: normalized_holder_name,
        bank_payload: bank_payload,
        ifsc_payload: ifsc_payload
      )

      cache_verification(result)

      return result
    end

    ensure_bank_account_verified!(bank_payload)
    name_at_bank = extract_name_at_bank(bank_payload)

    if name_at_bank.present? && !name_match?(expected: normalized_holder_name, actual: name_at_bank)
      raise StandardError, "Account holder name does not match the bank record"
    end

    result = VerificationResult.new(
      verification_reference: verification_reference,
      cashfree_reference_id: cashfree_reference_id,
      status: "verified",
      bank_name: bank_name,
      name_at_bank: name_at_bank.presence || normalized_holder_name,
      account_number: normalized_account_number,
      ifsc_code: normalized_ifsc,
      account_holder_name: normalized_holder_name,
      bank_payload: bank_payload,
      ifsc_payload: ifsc_payload
    )

    cache_verification(result)
    result
  end

  def consume_verified_payload!(verification_reference:, account_number:, ifsc_code:, account_holder_name:)
    payload = Rails.cache.read(cache_key(verification_reference))
    raise StandardError, "Bank verification expired. Please verify again." if payload.blank?

    unless payload[:dealer_id].to_i == @dealer.id
      raise StandardError, "Bank verification does not belong to this dealer"
    end

    normalized_account_number = account_number.to_s.gsub(/\s+/, "")
    normalized_ifsc = ifsc_code.to_s.strip.upcase
    normalized_holder_name = account_holder_name.to_s.squish

    unless payload[:account_number].to_s == normalized_account_number &&
           payload[:ifsc_code].to_s == normalized_ifsc &&
           payload[:account_holder_name].to_s.casecmp?(normalized_holder_name)
      raise StandardError, "Verified bank details do not match the current form"
    end

    payload
  end

  def persist_verified_profile!(profile:, verification_payload:)
    profile.assign_attributes(
      bank_name: verification_payload[:bank_name],
      verified_bank_name: verification_payload[:bank_name],
      bank_account_number: verification_payload[:account_number],
      ifsc_code: verification_payload[:ifsc_code],
      account_holder_name: verification_payload[:account_holder_name],
      verified_name_at_bank: verification_payload[:name_at_bank],
      bank_verification_status: "verified",
      bank_verification_reference: verification_payload[:verification_reference],
      bank_verified_at: Time.current,
      last_bank_verification_error: nil,
      bank_verification_payload: {
        verified_at: Time.current.iso8601,
        bank_verification: verification_payload[:bank_payload],
        ifsc_verification: verification_payload[:ifsc_payload]
      }
    )
    profile
  end

  def mark_unverified!(profile:, reason: nil)
    profile.assign_attributes(
      bank_verification_status: "unverified",
      bank_verification_reference: nil,
      bank_verified_at: nil,
      verified_bank_name: nil,
      verified_name_at_bank: nil,
      last_bank_verification_error: reason,
      bank_verification_payload: {}
    )
  end

  private

  def cache_verification(result)
    Rails.cache.write(
      cache_key(result.verification_reference),
      {
        dealer_id: @dealer.id,
        verification_reference: result.verification_reference,
        cashfree_reference_id: result.cashfree_reference_id,
        status: result.status,
        bank_name: result.bank_name,
        name_at_bank: result.name_at_bank,
        account_number: result.account_number,
        ifsc_code: result.ifsc_code,
        account_holder_name: result.account_holder_name,
        bank_payload: result.bank_payload,
        ifsc_payload: result.ifsc_payload
      },
      expires_in: CACHE_TTL
    )
  end

  def cache_key(verification_reference)
    "#{CACHE_PREFIX}:#{@dealer.id}:#{verification_reference}"
  end

  def extract_bank_name(ifsc_payload)
    ifsc_payload["bank"].presence ||
      ifsc_payload.dig("data", "bank").presence ||
      ifsc_payload.dig("data", "details", "bank").presence
  end

  def extract_name_at_bank(bank_payload)
    bank_payload["nameAtBank"].presence ||
      bank_payload["beneName"].presence ||
      bank_payload.dig("data", "nameAtBank").presence ||
      bank_payload.dig("data", "beneficiary_name").presence
  end

  def ensure_bank_account_verified!(bank_payload)
    account_exists = bank_payload["accountExists"]
    account_exists = bank_payload.dig("data", "accountExists") if account_exists.nil?
    account_exists = bank_payload.dig("data", "account_exists") if account_exists.nil?
    account_exists = bank_payload["status"].to_s.casecmp("VALID").zero? if account_exists.nil?

    return if ActiveModel::Type::Boolean.new.cast(account_exists)

    message = bank_payload["message"].presence ||
              bank_payload["subCodeMessage"].presence ||
              bank_payload.dig("data", "message").presence ||
              "Bank account verification failed"
    raise StandardError, message
  end

  def name_match?(expected:, actual:)
    normalize_name(expected) == normalize_name(actual)
  end

  def normalize_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end
end
