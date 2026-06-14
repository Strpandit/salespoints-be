class AdminOfferLetterPdf
  def initialize(admin)
    @admin = admin
  end

  def render
    Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
      pdf.text "SALESPOINTS INDIA PVT. LTD.", size: 24, style: :bold, color: "0B5ED7", align: :center
      pdf.text "ELECTRONICS COMMERCE PLATFORM", size: 11, style: :bold, color: "555555", align: :center
      pdf.move_down 8
      pdf.stroke_color "0B5ED7"
      pdf.line_width = 1.5
      pdf.stroke_horizontal_rule

      pdf.move_down 20

      pdf.text "OFFER LETTER",
               size: 16,
               style: :bold,
               align: :center

      pdf.move_down 20

      pdf.text "Ref No: SPINAD-#{@admin.id}/#{Date.current.year}",
               size: 11

      pdf.text "Date: #{Date.current.strftime('%d-%m-%Y')}",
               size: 11

      pdf.move_down 20

      pdf.text "Dear #{@admin.full_name.presence || 'Team Member'},", size: 12, style: :bold
      pdf.move_down 10
      pdf.text <<~TEXT,
        We are pleased to offer you the position of #{@admin.roles.active.pluck(:name).join(", ").presence || "Pending assignment"}
        in our organization SalesPoints India Pvt. Ltd. and Salespoints.in Retails store.

        Your date of joining shall be effective from #{formatted_date(@admin.joining_date)}.

        You will be responsible for handling assigned roles and responsibilities related to your position.

        Your monthly salary will be Rs.#{formatted_salary(@admin.salary)} in hand and you will be eligible for benefits and incentives 
        depends on your work profile and performance as applicable under company policy.

        We are confident that your skills, dedication and professional approach will contribute significantly to the continued growth
        and success of our organisation.
        TEXT

        size: 11,
        leading: 4
      pdf.move_down 20

      section_heading(pdf, "PERSONAL DETAILS")

      info_row(pdf, "Full Name", @admin.full_name)
      info_row(pdf, "Email", @admin.email)
      info_row(pdf, "Primary Mobile", format_phone(@admin.phone))

      pdf.move_down 15

      section_heading(pdf, "KEY RESPONSIBILITIES")

      responsibilities = [
        "New market open & pincodes",
        "Dealer onboarding and management",
        "Dealer Product listing and catalogue management",
        "Help & Guide for dealer to buy & sell products on our platform",
        "Manage dealer inventory and updated stocks on regular basis",
        "Help & Guide dealers for create & buy wholesale posts on our platform",
        "Customer support and issue resolution",
        "Sales and business development activities",
        "Coordination with internal teams",
        "Managing platform operations efficiently",
        "Don't Share any personal or confidential information with any dealers.",
      ]

      responsibilities.each do |item|
        pdf.text "- #{item}", size: 10.5
      end

      pdf.move_down 15

      section_heading(pdf, "REQUIRED FEW DOCS COMPLETE JOINING PROCESS")

      documents = [
        "Aadhaar Card",
        "PAN Card",
        "Bank Details",
        "Passport Size Photographs",
        "Educational Certificates"
      ]

      documents.each do |item|
        pdf.text "- #{item}", size: 10.5
      end

      pdf.move_down 15

      section_heading(pdf, "TERMS & CONDITIONS")

      terms = [
        "Employment is subject to successful verification of all submitted documents.",
        "Company policies and procedures must be followed at all times.",
        "Confidential company information must not be disclosed to any third party.",
        "The company reserves the right to modify responsibilities based on business requirements.",
        "Either party may terminate employment as per applicable company policy."
      ]

      terms.each_with_index do |term, index|
        pdf.text "#{index + 1}. #{term}",
                 size: 10.5,
                 leading: 3
      end

      pdf.move_down 25

      pdf.move_down 10

      pdf.text "Regards,", size: 11

      pdf.move_down 5

      pdf.text "SalesPoints India Pvt. Ltd.",
              size: 11,
              style: :bold,
              color: "0B5ED7"

      pdf.text "Address: Your Complete Company Address Here",
              size: 9,
              color: "555555"

      pdf.text "GST No.: 09ABCDE1234F1Z5",
              size: 9,
              color: "555555"

      pdf.text "TIN No.: 12345678901",
              size: 9,
              color: "555555"


    end.render
  end

  private

  def section_heading(pdf, title)
    pdf.text title,
             size: 13,
             style: :bold,
             color: "0B5ED7"

    pdf.move_down 5
  end

  def info_row(pdf, label, value)
    pdf.text(
      "<b>#{label}:</b> #{value.presence || 'N/A'}",
      inline_format: true,
      size: 10.5
    )
  end

  def formatted_salary(value)
    return "0" if value.blank?

    value.to_s.reverse.scan(/.{1,3}/).join(",").reverse
  end

  def formatted_date(date)
    return "N/A" if date.blank?

    date.strftime("%d-%m-%Y")
  end

  def format_phone(phone)
    return nil if phone.blank?

    "+91 #{phone}"
  end
end
