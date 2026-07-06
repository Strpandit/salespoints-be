require "net/http"
require "uri"
require "json"

class MetaWhatsappCloudService
  GRAPH_BASE = "https://graph.facebook.com".freeze

  TEMPLATE_DEALER_ORDER_REQUEST = "dealer_order_request"
  TEMPLATE_PAYMENT_REQUEST = "b2b_payment_request"
  TEMPLATE_ORDER_ACCEPT = "order_accept"
  TEMPLATE_PAYMENT_SUCCESS = "payment_success_order_details"

  def send_dealer_order_request(to:, product:, variant:, sku:, price:, quantity:, total_amount:, delivery_location:, approx_distance:, accept_token:, reject_token:, image_url: nil)
    components = []
    image_to_use = image_url.presence || "#{ENV['FRONTEND_URL']}/images/ac.png"

    components << {
      type: "header",
      parameters: [
        {
          type: "image",
          image: {
            link: image_to_use
          }
        }
      ]
    }

    components << {
      type: "body",
      parameters: [
        { type: "text", text: product.to_s },          
        { type: "text", text: variant.to_s },          
        { type: "text", text: sku.to_s },              
        { type: "text", text: price.to_s },            
        { type: "text", text: quantity.to_s },         
        { type: "text", text: total_amount.to_s },     
        { type: "text", text: delivery_location.to_s },
        { type: "text", text: approx_distance.to_s }   
      ]
    }

    components << {
      type: "button",
      sub_type: "quick_reply",
      index: 0,
      parameters: [
        { type: "payload", payload: accept_token.to_s }
      ]
    }

    components << {
      type: "button",
      sub_type: "quick_reply",
      index: 1,
      parameters: [
        { type: "payload", payload: reject_token.to_s }
      ]
    }

    send_template_message(
      to: to,
      template_name: TEMPLATE_DEALER_ORDER_REQUEST,
      components: components
    )
  end

  def send_order_accept(to:, dealer_code:, phone:, address:, order_id:, latitude:, longitude:, location_name:)
    name = "Salespoints Dealer Point #{dealer_code.presence || 'N/A'}"
    components = [
      {
        type: "header",
        parameters: [
          { 
            type: "location", 
            location: {
              latitude: latitude.to_s,
              longitude: longitude.to_s,
              name: name,
              address: address.to_s
            }
          }
        ]
      },
      {
        type: "body",
        parameters: [
          { type: "text", text: dealer_code.to_s },
          { type: "text", text: phone.to_s },      
          { type: "text", text: address.to_s },    
          { type: "text", text: order_id.to_s }    
        ]
      }
    ]

    send_template_message(
      to: to,
      template_name: TEMPLATE_ORDER_ACCEPT,
      components: components
    )
  end

  def send_payment_request(to:, product:, variant:, unit_price:, quantity:, total_amount:, payment_url:)
    components = [
      {
        type: "body",
        parameters: [
          { type: "text", text: product.to_s },    
          { type: "text", text: variant.to_s },    
          { type: "text", text: unit_price.to_s }, 
          { type: "text", text: quantity.to_s },   
          { type: "text", text: total_amount.to_s }
        ]
      },
      {
        type: "button",
        sub_type: "url",
        index: 0,
        parameters: [
          { type: "text", text: payment_url.to_s }
        ]
      }
    ]

    send_template_message(
      to: to,
      template_name: TEMPLATE_PAYMENT_REQUEST,
      components: components
    )
  end

  def send_payment_success(to:, product:, variant:, quantity:, unit_price:, total_paid:, payment_id:, order_id:, dealer_code:, dealer_phone:)
    components = [
      {
        type: "body",
        parameters: [
          { type: "text", text: product.to_s },    
          { type: "text", text: variant.to_s },    
          { type: "text", text: quantity.to_s },   
          { type: "text", text: unit_price.to_s }, 
          { type: "text", text: total_paid.to_s }, 
          { type: "text", text: payment_id.to_s }, 
          { type: "text", text: order_id.to_s },   
          { type: "text", text: dealer_code.to_s },
          { type: "text", text: dealer_phone.to_s }
        ]
      }
    ]
    send_template_message(
      to: to,
      template_name: TEMPLATE_PAYMENT_SUCCESS,
      components: components
    )
  end

  def send_template_message(to:, template_name:, components: [], language: "en")
    return unless configured?
    return if to.blank?

    payload = {
      messaging_product: "whatsapp",
      to: normalized_destination(to),
      type: "template",
      template: {
        name: template_name,
        language: { code: language },
        components: components
      }
    }
    response = post_message!(payload)
    response
  end

  def send_text_message(to:, body:)
    post_message!(
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: normalized_destination(to),
      type: "text",
      text: {
        preview_url: false,
        body: body.to_s.truncate(4_000)
      }
    )
  end

  def configured?
    access_token.present? && phone_number_id.present?
  end

  def post_message!(payload)
    Rails.logger.info "========== META REQUEST =========="
    Rails.logger.info endpoint
    Rails.logger.info JSON.pretty_generate(payload)
    uri = URI(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)

    response = http_client(uri).request(request)
   
    Rails.logger.info "========== META RESPONSE =========="
    Rails.logger.info response.code
    Rails.logger.info response.body
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    raise StandardError, "Meta WhatsApp API error #{response.code}: #{response.body}"
  end

  private

  def access_token
    ENV["META_WHATSAPP_ACCESS_TOKEN"].to_s.presence
  end

  def phone_number_id
    ENV["META_WHATSAPP_PHONE_NUMBER_ID"].to_s.presence
  end

  def api_version
    ENV["META_WHATSAPP_API_VERSION"].to_s.presence || "v23.0"
  end

  def endpoint
    "#{GRAPH_BASE}/#{api_version}/#{phone_number_id}/messages"
  end

  def normalized_destination(to)
    to.to_s.delete_prefix("+")
  end

  def e164_for(receiver)
    phone = receiver.try(:phone).to_s.gsub(/\s+/, "")
    return nil if phone.blank?

    cc = receiver.try(:country_code).to_s.strip
    cc = "+91" if cc.blank?
    cc = "+#{cc.delete_prefix('+')}" unless cc.start_with?("+")

    combined = "#{cc}#{phone.gsub(/\A\+/, '')}"
    parsed = Phonelib.parse(combined)
    parsed.valid? ? parsed.e164 : nil
  end

  def http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 20
    http.open_timeout = 10
    http
  end
end
