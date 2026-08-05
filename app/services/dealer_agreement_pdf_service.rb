require 'prawn'

class DealerAgreementPdfService
  def self.generate(dealer = nil)
    pdf = Prawn::Document.new(
      page_size: 'A4',
      margin: [36, 36, 45, 36]
    )

    # Primary colors
    navy_blue = "0F172A"
    brand_blue = "1D4ED8"
    dark_gray = "334155"
    light_bg = "F8FAFC"
    border_color = "CBD5E1"

    pdf.fill_color navy_blue
    pdf.text "SALESPOINTS INDIA PVT. LTD.", size: 16, style: :bold, align: :center
    pdf.move_down 3
    pdf.fill_color brand_blue
    pdf.text "Dealer Onboarding Terms & Conditions", size: 12, style: :bold, align: :center
    pdf.move_down 3
    pdf.fill_color "64748B"
    pdf.text "Effective Date: July 30, 2026", size: 8.5, align: :center
    pdf.move_down 10

    pdf.stroke_color border_color
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    if dealer.present?
      dealer_name = dealer.try(:full_name).presence || "#{dealer.try(:first_name)} #{dealer.try(:last_name)}".strip
      pdf.fill_color light_bg
      pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 24
      pdf.fill_color navy_blue
      pdf.move_down 6
      pdf.indent(8) do
        pdf.text "Issued To: #{dealer_name.presence || 'Dealer'} (#{dealer.email})  |  Generated: #{Time.current.strftime('%d %b %Y, %I:%M %p')}", size: 8.5, style: :bold
      end
      pdf.move_down 12
    end

    sections = [
      {
        title: "1. Dealer Eligibility",
        body: "To register as a dealer on the SalesPoints Marketplace, the following documents/details are required:\n" \
              "• Valid GST Registration (where applicable)\n" \
              "• PAN Card\n" \
              "• Aadhaar Card / Authorized Signatory ID\n" \
              "• Cancelled Cheque or Bank Proof\n" \
              "• Shop Establishment Certificate / Business Registration (where applicable)\n" \
              "• Valid Business Address\n" \
              "• Active Mobile Number\n" \
              "• Valid Email Address\n" \
              "• Current Bank Account (Preferred)\n" \
              "• Dealers without GST may use a Savings Bank Account, subject to SalesPoints approval."
      },
      {
        title: "2. Business Category",
        body: "Every dealer must select the appropriate business category during onboarding:\n" \
              "• Mobile Retailer\n" \
              "• Mobile Wholesaler\n" \
              "• Electronics Retailer\n" \
              "• Electronics Wholesaler\n" \
              "• Accessories Dealer\n" \
              "• Distributor\n" \
              "• Manufacturer\n" \
              "• Brand Authorized Dealer\n" \
              "• Other relevant categories approved by SalesPoints"
      },
      {
        title: "3. KYC Verification",
        body: "SalesPoints will verify:\n" \
              "• GST Registration\n" \
              "• PAN\n" \
              "• Bank Account\n" \
              "• Business Address\n" \
              "• Owner/Authorized Person Identity\n\n" \
              "Accounts will remain inactive until successful verification. SalesPoints reserves the right to request re-verification at any time."
      },
      {
        title: "4. Marketplace Commission",
        body: "B2B Orders:\n" \
              "Platform Commission: 1.25% (GST treatment shall be as per the Dealer Agreement).\n" \
              "Commission will be deducted before settlement.\n\n" \
              "B2C Orders:\n" \
              "Platform Commission: 2.25%\n" \
              "Commission will be deducted before settlement."
      },
      {
        title: "5. Payment Settlement",
        body: "Settlement TAT:\n" \
              "• Mobile Category – Up to 48 Hours\n" \
              "• Electronics – Up to 72 Hours\n" \
              "• Accessories & Mini Appliances – Up to 48 Hours\n\n" \
              "Settlement will be released only after:\n" \
              "• Successful delivery\n" \
              "• Return window closure (if applicable)\n" \
              "• Fraud review clearance\n" \
              "• Any applicable deductions"
      },
      {
        title: "6. Product Authenticity",
        body: "The dealer declares that:\n" \
              "• All products are 100% genuine.\n" \
              "• Counterfeit products will never be listed.\n" \
              "• Refurbished products shall not be sold as new.\n" \
              "• Imported products must be legally sourced.\n" \
              "• Valid GST purchase invoices must be available whenever required."
      },
      {
        title: "7. IMEI & Serial Number Compliance",
        body: "For Mobile & Electronics products:\n" \
              "• Correct IMEI and Serial Numbers must be maintained.\n" \
              "• Every dispatched product must match the listed IMEI/Serial Number.\n" \
              "• Duplicate or mismatched IMEI/Serial Numbers may result in immediate suspension."
      },
      {
        title: "8. Warranty Declaration",
        body: "Every listing must clearly specify:\n" \
              "• Brand Warranty\n" \
              "• Dealer Warranty\n" \
              "• No Warranty\n\n" \
              "Incorrect warranty claims may attract penalties or account suspension."
      },
      {
        title: "9. Stock Accuracy",
        body: "Only available inventory may be listed.\n\n" \
              "Repeated stock mismatch may result in:\n" \
              "• Listing disablement\n" \
              "• Lower search ranking\n" \
              "• Account suspension"
      },
      {
        title: "10. Dispatch & Delivery Timelines",
        body: "Maximum Dispatch Time: Within 24 Hours\n\n" \
              "Expected Delivery Timelines:\n" \
              "• B2B Orders: 1–2 Hours (Nearby Deliveries)\n" \
              "• B2C Orders: 4–8 Hours after Order Acceptance\n" \
              "• Wholesale Orders: Up to 12 Hours\n" \
              "• Distribution Orders: Up to 24 Hours\n\n" \
              "All deliveries should preferably be completed through Open Box Delivery with Serial Number/IMEI verification wherever applicable.\n" \
              "Delayed deliveries may reduce seller performance score and visibility. Try for fast deliveries."
      },
      {
        title: "11. Packaging & Billing",
        body: "Dealer responsibilities include:\n" \
              "• Proper Packaging\n" \
              "• Bubble Wrap Protection\n" \
              "• Tamper-Proof Packaging\n" \
              "• Product inspection before dispatch\n" \
              "• Correct invoice generation\n\n" \
              "You must not provide any proof of your shop, such as a bill, business card, or anything else that customers can use to contact you directly. If you do, your account may be suspended.\n" \
              "Invoices should not contain any information intended to divert customers away from the Sales Points marketplace."
      },
      {
        title: "12. Order Cancellation Policy",
        body: "If seller cancellation exceeds 10% continuously:\n" \
              "• Order visibility may be reduced.\n" \
              "• Seller ranking may decrease.\n\n" \
              "If an accepted order is cancelled by the seller:\n" \
              "• A cancellation charge of ₹500 per order may apply.\n" \
              "• The amount may be deducted from future settlements."
      },
      {
        title: "13. Returns & Investigation",
        body: "Excessive returns may trigger:\n" \
              "• Seller investigation\n" \
              "• Marketplace audit\n" \
              "• Product verification\n\n" \
              "If counterfeit or fraudulent products are found, permanent suspension may be imposed."
      },
      {
        title: "14. Customer Support",
        body: "Seller must:\n" \
              "• Respond to customer queries within 12 hours\n" \
              "• Resolve warranty-related cases promptly\n" \
              "• Cooperate with SalesPoints support team"
      },
      {
        title: "15. Pricing Policy",
        body: "The following are strictly prohibited:\n" \
              "• Fake Discounts\n" \
              "• Artificial Price Inflation\n" \
              "• Price Manipulation\n" \
              "• Dummy Listings\n\n" \
              "For wholesale listings, price changes before the permitted duration may require Admin Re-approval.\n" \
              "Marketplace reserves the right to regulate pricing policies for B2B and B2C transactions where applicable."
      },
      {
        title: "16. Fake Orders",
        body: "Strictly prohibited:\n" \
              "• Self-ordering\n" \
              "• Orders through relatives or associates to manipulate sales\n" \
              "• Fake cancellations\n" \
              "• Commission manipulation\n\n" \
              "Violation may result in permanent account termination."
      },
      {
        title: "17. Fake Reviews",
        body: "Fake Reviews, Fake Ratings, and Fake Comments are strictly prohibited.\n\n" \
              "Immediate action may include:\n" \
              "• Review removal\n" \
              "• Listing suspension\n" \
              "• Permanent seller ban"
      },
      {
        title: "18. Brand Authorization",
        body: "For premium brands such as Apple, Samsung, OnePlus, Xiaomi, Vivo, Oppo, Realme, Motorola, and other brands:\n" \
              "Seller must provide:\n" \
              "• Brand Authorization (if required)\n" \
              "• Valid GST Purchase Invoice\n" \
              "• Distributor/Brand Billing Proof"
      },
      {
        title: "19. Restricted Products",
        body: "The following products are prohibited:\n" \
              "• Stolen Devices\n" \
              "• Products without Invoice\n" \
              "• Counterfeit Products\n" \
              "• Duplicate Earbuds\n" \
              "• Illegal Software\n" \
              "• Pirated Accessories\n" \
              "• Any product prohibited by law"
      },
      {
        title: "20. Tax Compliance",
        body: "Seller is solely responsible for compliance with:\n" \
              "• GST\n" \
              "• TDS\n" \
              "• TCS\n" \
              "• Income Tax\n" \
              "• Any other applicable statutory requirements"
      },
      {
        title: "21. Data Protection",
        body: "Seller shall not misuse customer information for:\n" \
              "• WhatsApp Marketing\n" \
              "• Call Spam\n" \
              "• SMS Spam\n" \
              "• Email Spam\n" \
              "• Creating personal customer databases\n" \
              "• Direct marketing outside the marketplace\n\n" \
              "Violation may result in permanent suspension and legal action."
      },
      {
        title: "22. Marketplace Rights Reserved",
        body: "All rights relating to the operation, management, and administration of the marketplace are reserved by SalesPoints India Pvt. Ltd. The Company reserves the right to exercise the following rights at its sole discretion, subject to applicable laws:\n" \
              "1. Suspend, restrict, or permanently terminate any user or seller account found to be in violation of the Company's Terms & Conditions, Seller Policy, or applicable laws.\n" \
              "2. Reject, modify, remove, or disable any product listing, advertisement, image, description, or content that is inaccurate, misleading, counterfeit, unlawful, infringing, or otherwise violates Company policies.\n" \
              "3. Verify the identity, business registration, tax information, invoices, product authenticity, ownership, or any other documentation submitted by users or sellers.\n" \
              "4. Cancel or refuse any order where fraud, pricing errors, stock discrepancies, payment risks, policy violations, or other legitimate concerns are identified.\n" \
              "5. Hold, delay, adjust, or withhold settlements or payments where necessary for fraud prevention, dispute resolution, legal compliance, or policy enforcement.\n" \
              "6. Investigate complaints, disputes, suspicious activities, and policy violations, and take appropriate enforcement actions.\n" \
              "7. Modify, update, or discontinue any feature, service, commission structure, subscription plan, fee, policy, or marketplace functionality at any time.\n" \
              "8. Restrict or prohibit users from sharing personal contact information or conducting transactions outside the marketplace where such conduct violates Company policies.\n" \
              "9. Remove counterfeit, prohibited, unsafe, stolen, or otherwise unauthorized products from the platform without prior notice.\n" \
              "10. Take any action reasonably necessary to protect the integrity, security, reputation, and lawful operation of the marketplace.\n\n" \
              "All transactions initiated through the platform must be completed within the SalesPoints Marketplace."
      },
      {
        title: "23. Data Protection Rights Reserved",
        body: "SalesPoints India Pvt. Ltd. is committed to protecting user data and processing personal information in accordance with applicable data protection and privacy laws.\n\n" \
              "The Company reserves the right to:\n" \
              "1. Collect, store, process, and use personal, business, and transactional information required for account creation, order processing, payment processing, customer support, fraud prevention, legal compliance, and platform operations.\n" \
              "2. Verify user identity through KYC, GST, business registration, invoices, or other supporting documents where required.\n" \
              "3. Maintain security logs, transaction records, device information, IP addresses, and other technical data to detect fraud, unauthorized access, abuse, or security threats.\n" \
              "4. Share necessary information with payment gateways, logistics partners, cloud service providers, technology vendors, regulatory authorities, and law enforcement agencies where legally permitted or required.\n" \
              "5. Retain personal and transactional data for the period required by applicable laws, regulatory obligations, dispute resolution, tax compliance, fraud prevention, and legitimate business purposes.\n" \
              "6. Delete, anonymize, archive, or restrict access to data after the applicable retention period or as otherwise required by law.\n" \
              "7. Use marketplace data for analytics, performance improvement, security monitoring, service optimization, and business intelligence, provided that such use complies with applicable privacy laws.\n" \
              "8. Update or amend its Privacy Policy, Data Protection Policy, and data handling practices from time to time to reflect legal, regulatory, or operational requirements.\n" \
              "9. Disclose information where required by a court order, government authority, regulatory agency, or any applicable law.\n" \
              "10. Take all reasonable technical and organizational measures to protect user information from unauthorized access, misuse, alteration, disclosure, or destruction.\n\n" \
              "Nothing contained herein shall limit the statutory rights available to users under applicable law. All marketplace operations and data processing activities shall be carried out in accordance with applicable legal and regulatory requirements."
      },
      {
        title: "24. Indemnity",
        body: "If any legal issue arises due to the seller, including but not limited to:\n" \
              "• Consumer Complaints\n" \
              "• Court Cases\n" \
              "• GST Penalties\n" \
              "• Trademark Infringement\n" \
              "• Counterfeit Claims\n" \
              "• Government Investigations\n\n" \
              "The seller shall indemnify and hold harmless SalesPoints India Pvt. Ltd., its directors, employees, affiliates, and marketplace partners against all losses, penalties, claims, damages, legal expenses, and liabilities arising from such actions."
      },
      {
        title: "25. Dispute Resolution",
        body: "Any dispute shall be resolved in the following order:\n" \
              "1. Mutual Negotiation\n" \
              "2. Arbitration under applicable Indian laws\n" \
              "3. Competent Courts having jurisdiction"
      },
      {
        title: "26. Brand, Intellectual Property & Third-Party Claims",
        body: "The Dealer agrees that all products, brands, trademarks, images, descriptions, documents, and any other content listed by the Dealer on the SalesPoints Marketplace shall be the sole responsibility of the Dealer.\n\n" \
              "The Dealer confirms that it has all necessary rights, permissions, authorizations, ownership, or lawful sources required to sell, distribute, and list the products on the Marketplace.\n\n" \
              "If any brand owner, manufacturer, distributor, trademark owner, intellectual property rights holder, or any third party raises any objection, complaint, claim, legal notice, or dispute regarding the products listed by the Dealer, the Dealer shall be solely responsible for handling and resolving such matters.\n\n" \
              "The Dealer shall be responsible for addressing and resolving any such claims or disputes independently and, where required, shall provide all necessary documents, invoices, approvals, authorizations, or any other supporting evidence.\n\n" \
              "SalesPoints India Pvt. Ltd. only provides an online marketplace platform where Dealers can list their products and set up their online store. The Company does not guarantee or take responsibility for product ownership, authenticity, brand authorization, quality, warranty, intellectual property rights, or any third-party approvals.\n\n" \
              "For any dispute, claim, loss, penalty, damage, or legal action arising between the Dealer and any brand owner, manufacturer, distributor, or third party in relation to product listing, brand usage, trademark, copyright, authorization, or sale, SalesPoints India Pvt. Ltd. shall not be held responsible or liable in any manner.\n\n" \
              "The Dealer agrees that if any claim, legal action, financial loss, or expense arises against SalesPoints India Pvt. Ltd. due to the Dealer’s product listings, sales activities, unauthorized brand usage, counterfeit or fake products, violation of third-party rights, or any policy breach, the Dealer shall bear full responsibility and shall indemnify the Company.\n\n" \
              "SalesPoints India Pvt. Ltd. reserves the right to remove, restrict, or disable any disputed, unauthorized, risky, or policy-violating product listing and may also take appropriate action against the Dealer’s account if necessary."
      },
      {
        title: "26. Billing, Invoicing & Payment Processing Consent",
        body: "The Dealer acknowledges and agrees that, in order to manage the business operations of the SalesPoints Marketplace in a smooth, secure, and professional manner, the billing and payment processing shall be carried out through SalesPoints India Pvt. Ltd.\n\n" \
              "The Dealer agrees that, in certain transactions, the Dealer may generate invoices for its products in the name of SalesPoints India Pvt. Ltd., after which SalesPoints India Pvt. Ltd. shall issue the invoice to the end customer/buyer in accordance with the applicable process.\n\n" \
              "The Dealer understands and accepts that the purpose of this process is to ensure marketplace operations, customer experience, dealer privacy and security, transaction management, and business confidentiality.\n\n" \
              "The Dealer has no objection to this billing structure, invoicing process, payment collection mechanism, and settlement procedure.\n\n" \
              "The Dealer agrees that SalesPoints India Pvt. Ltd., after receiving payment from the buyer/customer, may deduct applicable charges, commission, service fees, taxes, adjustments, or other applicable deductions and transfer the remaining settlement amount to the Dealer.\n\n" \
              "The Dealer accepts that:\n" \
              "• The primary responsibility for product availability, product quality, authenticity, warranty, after-sales service, and all product-related obligations shall remain with the Dealer.\n" \
              "• The billing and payment processing structure followed by SalesPoints India Pvt. Ltd. is based on the Dealer’s consent and agreement.\n" \
              "• The Dealer shall not raise any objection, dispute, or claim in relation to this process in the future, provided that the Company is acting in accordance with agreed terms and applicable laws.\n\n" \
              "SalesPoints India Pvt. Ltd. shall have the right to update, modify, or change the billing, invoicing, and settlement process as per marketplace requirements, legal compliance, and operational convenience."
      },
      {
        title: "26. Acceptance",
        body: "By registering, accessing, or using the SalesPoints Marketplace, the Dealer acknowledges, represents, and agrees that:\n" \
              "1. All information, documents, and details provided to SalesPoints India Pvt. Ltd. are true, accurate, complete, and up to date.\n" \
              "2. The Dealer has read, understood, and agrees to comply with these Terms & Conditions, the Seller Policy, Privacy Policy, and all other applicable marketplace policies.\n" \
              "3. The Dealer shall comply with all applicable laws, regulations, and industry standards while using the Marketplace.\n" \
              "4. The Dealer accepts that SalesPoints India Pvt. Ltd. may amend, modify, or update these Terms & Conditions, policies, fees, or operational procedures from time to time. Continued use of the Marketplace after such updates shall constitute the Dealer's acceptance of the revised terms.\n" \
              "5. The Dealer agrees to cooperate with SalesPoints India Pvt. Ltd. in any verification, compliance, audit, investigation, or dispute resolution process relating to the Dealer's use of the Marketplace.\n" \
              "6. If the Dealer does not agree with any provision of these Terms & Conditions or any future amendments, the Dealer must discontinue the use of the Marketplace and may request closure of the Dealer account in accordance with the Company's policies."
      }
    ]

    sections.each do |sec|
      pdf.fill_color brand_blue
      pdf.text sec[:title], size: 10, style: :bold
      pdf.move_down 4

      pdf.fill_color dark_gray
      pdf.text sec[:body], size: 8.5, leading: 2.5
      pdf.move_down 10
    end

    pdf.move_down 10
    pdf.stroke_color border_color
    pdf.stroke_horizontal_rule
    pdf.move_down 8

    pdf.fill_color "64748B"
    pdf.text "SalesPoints India Pvt. Ltd. | Official Dealer Onboarding Agreement", size: 8, align: :center

    pdf.render
  end
end
