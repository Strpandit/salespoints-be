# Email Notification System Documentation

## Overview
The SalesPoints application now includes a comprehensive email notification system that automatically sends emails to dealers and admins for various actions throughout the platform.

## Email Types

### 1. Dealer Emails

#### Welcome Email (DealerMailer#welcome_email)
- **Triggered**: When a dealer account is created
- **Recipients**: Newly registered dealer
- **Contents**:
  - Business credentials (email and temporary password)
  - Next steps for account onboarding
  - Information that account is pending approval
  - Link to dealer portal

#### Approval Email (DealerMailer#approval_email)
- **Triggered**: When a dealer is approved by admin
- **Recipients**: Approved dealer
- **Contents**:
  - Celebration message
  - List of platform features available
  - Direct link to dealer dashboard
  - Next steps (adding products, inventory management)

#### Rejection Email (DealerMailer#rejection_email)
- **Triggered**: When a dealer application is rejected
- **Recipients**: Rejected dealer
- **Contents**:
  - Explanation message
  - Optional reason for rejection
  - Guidance on next steps
  - Option to reapply

### 2. Admin Notification Emails

#### Entity Creation Email (AdminNotificationMailer#entity_created)
- **Sent when**: New brands, categories, products, roles, customers, admins, dealers, or orders are created
- **Recipients**: All super admin users
- **Contents**:
  - Entity type (e.g., "Brand", "Category", "Dealer")
  - Entity name
  - Who created it (created_by)
  - Timestamp

#### Entity Update Email (AdminNotificationMailer#entity_updated)
- **Sent when**: Existing entities are modified
- **Recipients**: All super admin users
- **Contents**:
  - Entity type and name
  - Who updated it
  - Timestamp

#### Entity Deletion Email (AdminNotificationMailer#entity_deleted)
- **Sent when**: Entities are deleted from the system
- **Recipients**: All super admin users
- **Contents**:
  - Entity type and name
  - Who deleted it
  - Warning banner (red theme)

#### Dealer Action Email (AdminNotificationMailer#dealer_action)
- **Sent when**: Dealers are approved, rejected, blocked, unblocked, or reverted to pending
- **Recipients**: All super admin users
- **Contents**:
  - Dealer name
  - Action performed (approved/rejected/blocked/unblocked/reverted_to_pending)
  - Details (rejection reason, etc.)
  - Timestamp

#### Product Action Email (AdminNotificationMailer#product_action)
- **Sent when**: Dealer products are approved, rejected, or reverted to pending
- **Recipients**: All super admin users
- **Contents**:
  - Product name
  - Dealer name (who submitted)
  - Action performed (approved/rejected/reverted_to_pending)
  - Details (rejection reason, etc.)
  - Timestamp

## Configuration

### Mailer Configuration Files
- **ApplicationMailer**: Base mailer class with default from address
  - Default from: `no-reply@salespoints.com`
  - Location: `app/mailers/application_mailer.rb`

### SMTP Configuration
Default SMTP settings are configured in:
- Development: `config/environments/development.rb`
- Production: `config/environments/production.rb`
- Test: `config/environments/test.rb`

### Environment Variables (Optional)
You can customize these via environment variables:
- `MAILER_FROM_EMAIL`: Custom from email address (Default: no-reply@salespoints.com)
- `DEALER_LOGIN_URL`: URL for dealer login (used in email templates)
- `DEALER_SIGNUP_URL`: URL for dealer signup (used in email templates)

## Controller Integration

### DealersController Changes
1. **Create action**: 
   - Generates temporary password using SecureRandom.hex(6)
   - Sends welcome email with credentials
   - Notifies super admins about new dealer

2. **Approve action**:
   - Sends approval email to dealer
   - Notifies super admins about approval

3. **Reject action**:
   - Accepts optional `reason` parameter
   - Sends rejection email with reason
   - Notifies super admins about rejection

### DealerProductsController Changes
1. **Approve action**:
   - Notifies super admins about product approval

2. **Reject action**:
   - Accepts optional `reason` parameter
   - Notifies super admins about rejection

3. **Revert to Pending action**:
   - Notifies super admins about revert action

## Email Templates

All email templates use professional HTML design with:
- Gradient headers (color-coded by action type)
- Inline CSS for email client compatibility
- Responsive design
- Color-coded sections:
  - Purple: Dealer creation/action notifications
  - Green: Approvals
  - Orange: Updates
  - Red: Deletions/Rejections
  - Pink: Rejection reasons

### Template Locations
```
app/views/dealer_mailer/
  ├── welcome_email.html.erb
  ├── approval_email.html.erb
  └── rejection_email.html.erb

app/views/admin_notification_mailer/
  ├── entity_created.html.erb
  ├── entity_updated.html.erb
  ├── entity_deleted.html.erb
  ├── dealer_action.html.erb
  └── product_action.html.erb
```

## Admin Email Recipients

Emails are sent to all AdminUser records where `is_super_admin = true`.

Query used in controllers:
```ruby
AdminUser.where(is_super_admin: true).pluck(:email)
```

## Helper Methods

### In DealersController
- `get_admin_emails`: Returns array of super admin email addresses
- `notify_admins_about_dealer_creation(dealer)`: Sends creation notification
- `notify_admins_about_dealer_action(dealer, action, details)`: Sends action notification

### In DealerProductsController
- `get_admin_emails`: Returns array of super admin email addresses
- `notify_admins_about_product_action(product_name, dealer_name, action, details)`: Sends product action notification

## Testing

### In Development
Emails are delivered via SMTP based on `development.rb` configuration.

### In Test
Emails are stored in `ActionMailer::Base.deliveries` array.

### Email Preview
To preview emails in development:
Visit `http://localhost:3000/rails/mailers/dealer_mailer/welcome_email`

## API Endpoints

### Dealer Creation
```
POST /api/dealers
Body: {
  dealer: {
    first_name: "...",
    last_name: "...",
    email: "...",
    ...
  }
}
Response: Includes success message about welcome email
```

### Dealer Approval
```
PATCH /api/dealers/:id/approve
Response: Includes success message about approval email
```

### Dealer Rejection
```
PATCH /api/dealers/:id/reject
Body: { reason: "Optional rejection reason" }
Response: Includes success message about rejection email
```

### Product Approval
```
PATCH /api/dealer_products/:id/approve
Response: Includes success message about approval notification
```

### Product Rejection
```
PATCH /api/dealer_products/:id/reject
Body: { reason: "Optional rejection reason" }
Response: Includes success message about rejection notification
```

### Product Revert to Pending
```
PATCH /api/dealer_products/:id/revert_to_pending
Response: Includes success message about revert notification
```

## Best Practices

1. **Password Generation**: Temporary passwords are auto-generated as hex strings for security
2. **Async Delivery**: All emails use `.deliver_later` for non-blocking delivery
3. **Super Admins Only**: Admin notifications only go to super admins to avoid noise
4. **Optional Details**: Rejection reasons and other details are optional fields
5. **Timestamp Tracking**: All notifications include server timestamp for audit trail

## Troubleshooting

### Emails Not Sending
1. Check SMTP configuration in `config/environments/{env}.rb`
2. Verify `action_mailer.perform_deliveries` is `true`
3. Check logs for mailer errors: `tail -f log/development.log`
4. Ensure super admin users exist with valid email addresses

### Email Variables Missing
- Verify instance variables are set in mailer methods
- Check email template variable names match mailer variables
- Look for typos in template variable references (e.g., `@dealer` vs `@dealer_name`)

### Template Not Found
- Verify template file exists in correct view directory
- Check file naming: `action_name.html.erb` format
- Restart Rails server after adding new templates

## Future Enhancements

1. **Email Templates**: Additional templates for other entity CRUD operations
2. **Email Preferences**: Allow admins to opt-in/out of certain notifications
3. **Email Queues**: Implement background jobs for bulk email sending
4. **HTML Email Editor**: UI for customizing email templates
5. **Email Analytics**: Track opens, clicks, delivery failures
6. **Retry Logic**: Automatic retry for failed email deliveries
