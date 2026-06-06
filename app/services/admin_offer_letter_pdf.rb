class AdminOfferLetterPdf
  def initialize(admin)
    @admin = admin
  end

  def render
    Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
      pdf.text "SalesPoints", size: 24, style: :bold, align: :center
      pdf.move_down 6
      pdf.text "Offer Letter / Joining Summary", size: 14, align: :center
      pdf.move_down 24

      pdf.text "Date: #{Time.current.strftime('%d %B %Y')}", size: 11
      pdf.move_down 16

      pdf.text "Dear #{@admin.full_name.presence || 'Team Member'},", size: 12
      pdf.move_down 10
      pdf.text(
        "This document records the onboarding and joining details submitted for your SalesPoints admin account. " \
        "Please retain this copy for your records.",
        size: 11,
        leading: 4
      )
      pdf.move_down 18

      add_section(pdf, "Personal Details", [
        ["Full Name", @admin.full_name],
        ["Email", @admin.email],
        ["Primary Mobile", format_phone(@admin.phone)],
        ["Alternate Mobile", format_phone(@admin.alternate_phone)],
        ["Address", @admin.address]
      ])

      add_section(pdf, "Identity Details", [
        ["Aadhaar Number", @admin.aadhar_number],
        ["PAN Number", @admin.pan_number]
      ])

      add_section(pdf, "Bank Details", [
        ["Bank Name", @admin.bank_name],
        ["Account Holder Name", @admin.account_holder_name],
        ["Account Number", @admin.bank_account_number],
        ["IFSC Code", @admin.ifsc_code]
      ])

      add_section(pdf, "Academic Details", [
        ["10th School", @admin.tenth_school_name],
        ["10th Board", @admin.tenth_board],
        ["10th Passing Year", @admin.tenth_passing_year],
        ["10th Percentage", @admin.tenth_percentage],
        ["12th School", @admin.twelfth_school_name],
        ["12th Board", @admin.twelfth_board],
        ["12th Passing Year", @admin.twelfth_passing_year],
        ["12th Percentage", @admin.twelfth_percentage]
      ])

      add_section(pdf, "Role Assignment", [
        ["Assigned Roles", @admin.roles.active.pluck(:name).join(", ").presence || "Pending assignment"],
        ["Approval Status", @admin.approval_status.to_s.humanize]
      ])

      pdf.move_down 18
      pdf.text "Regards,", size: 11
      pdf.text "SalesPoints HR & Admin Team", size: 11, style: :bold
    end.render
  end

  private

  def add_section(pdf, title, rows)
    pdf.move_down 10
    pdf.text title, size: 13, style: :bold, color: "1F3A5F"
    pdf.move_down 6
    rows.each do |label, value|
      pdf.text "<b>#{label}:</b> #{value.presence || 'N/A'}", inline_format: true, size: 10.5, leading: 3
      pdf.move_down 2
    end
  end

  def format_phone(value)
    return nil if value.blank?

    ["+91", value].compact.join(" ")
  end
end
