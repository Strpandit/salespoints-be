class JsonWebToken
  SECRET = Rails.application.credentials.jwt_secret || Rails.application.secret_key_base
  ALGORITHM = 'HS256'

  def self.encode(payload, exp = 24.hours.from_now)
    JWT.encode(payload.merge(exp: exp.to_i), SECRET, ALGORITHM)
  end

  def self.decode(token)
    JWT.decode(token, SECRET, true, algorithm: ALGORITHM)[0].with_indifferent_access
  end

end
