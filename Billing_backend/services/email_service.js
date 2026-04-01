// services/email_service.js - Email notification service
const nodemailer = require('nodemailer');

class EmailService {
  constructor() {
    this.transporter = null;
    this.initialized = false;
  }

  // Initialize email transporter
  initialize() {
    try {
      const emailConfig = {
        host: process.env.SMTP_HOST || 'smtp.gmail.com',
        port: parseInt(process.env.SMTP_PORT || '587'),
        secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASSWORD,
        },
      };

      // Validate configuration
      if (!emailConfig.auth.user || !emailConfig.auth.pass) {
        console.warn('⚠️ Email service not configured. Set SMTP_USER and SMTP_PASSWORD in .env');
        return false;
      }

      this.transporter = nodemailer.createTransport(emailConfig);
      this.initialized = true;
      
      console.log('✅ Email service initialized');
      return true;
    } catch (error) {
      console.error('❌ Failed to initialize email service:', error);
      return false;
    }
  }

  // Verify email configuration
  async verifyConnection() {
    if (!this.initialized || !this.transporter) {
      return false;
    }

    try {
      await this.transporter.verify();
      console.log('✅ Email server connection verified');
      return true;
    } catch (error) {
      console.error('❌ Email server connection failed:', error);
      return false;
    }
  }

  // Send customer approval email (with or without password setup link)
  async sendCustomerApprovalEmail({ email, name, companyName, passwordResetLink }) {
    console.log('\n' + '='.repeat(80));
    console.log('📧 EMAIL SERVICE - SEND CUSTOMER APPROVAL EMAIL');
    console.log('='.repeat(80));
    console.log('🔹 Recipient Email:', email);
    console.log('🔹 Recipient Name:', name);
    console.log('🔹 Company Name:', companyName || 'N/A');
    console.log('🔹 Password Reset Link:', passwordResetLink ? 'YES (provided)' : 'NO');
    console.log('🔹 Timestamp:', new Date().toISOString());
    console.log('-'.repeat(80));
    
    if (!this.initialized || !this.transporter) {
      console.log('❌ FAILED: Email service not initialized');
      console.log('🔹 Initialized:', this.initialized);
      console.log('🔹 Transporter:', !!this.transporter);
      console.log('🔹 SMTP_USER:', process.env.SMTP_USER ? 'SET' : 'NOT SET');
      console.log('🔹 SMTP_PASSWORD:', process.env.SMTP_PASSWORD ? 'SET' : 'NOT SET');
      console.log('='.repeat(80) + '\n');
      return { success: false, error: 'Email service not configured' };
    }

    console.log('✅ Email service is initialized');
    console.log('🔹 SMTP Host:', process.env.SMTP_HOST || 'smtp.gmail.com');
    console.log('🔹 SMTP Port:', process.env.SMTP_PORT || '587');
    console.log('🔹 SMTP User:', process.env.SMTP_USER);

    const templates = require('./email_templates');

    try {
      // Use different template based on whether password setup is needed
      const isPasswordSetupNeeded = !!passwordResetLink;
      
      console.log('-'.repeat(80));
      console.log('📝 Email Type:', isPasswordSetupNeeded ? 'WELCOME + PASSWORD SETUP' : 'APPROVAL ONLY');
      
      const mailOptions = {
        from: `"Abra Travels Support" <${process.env.SMTP_USER}>`,
        to: email,
        subject: isPasswordSetupNeeded 
          ? '🎉 Welcome to Abra Travels - Set Your Password'
          : '🎉 Your Abra Travels Account Has Been Approved!',
        html: isPasswordSetupNeeded
          ? templates.getWelcomeWithPasswordSetupTemplate(name, email, companyName, passwordResetLink)
          : templates.getApprovalEmailTemplate(name, email, companyName),
        text: isPasswordSetupNeeded
          ? templates.getWelcomeWithPasswordSetupText(name, email, companyName, passwordResetLink)
          : templates.getApprovalEmailText(name, email, companyName),
      };

      console.log('📦 Mail Options:');
      console.log('   From:', mailOptions.from);
      console.log('   To:', mailOptions.to);
      console.log('   Subject:', mailOptions.subject);
      console.log('   HTML Length:', mailOptions.html.length, 'characters');
      console.log('   Text Length:', mailOptions.text.length, 'characters');
      console.log('-'.repeat(80));
      console.log('📤 Sending email via SMTP...');

      const info = await this.transporter.sendMail(mailOptions);
      
      console.log('='.repeat(80));
      console.log('✅ SUCCESS: Email sent successfully!');
      console.log('🔹 Message ID:', info.messageId);
      console.log('🔹 Response:', info.response);
      console.log('🔹 Accepted:', info.accepted);
      console.log('🔹 Rejected:', info.rejected);
      console.log('🔹 Email Type:', isPasswordSetupNeeded ? 'Welcome + Password Setup' : 'Approval');
      console.log('🔹 Recipient:', email);
      console.log('='.repeat(80) + '\n');
      
      return { success: true, messageId: info.messageId };
    } catch (error) {
      console.log('='.repeat(80));
      console.log('❌ FAILED: Error sending email');
      console.log('🔹 Error Message:', error.message);
      console.log('🔹 Error Code:', error.code);
      console.log('🔹 Error Command:', error.command);
      console.log('🔹 Full Error:', error);
      console.log('='.repeat(80) + '\n');
      return { success: false, error: error.message };
    }
  }

  // HTML email template for approval
  getApprovalEmailTemplate(name, email, companyName, passwordResetLink) {
    const passwordSection = passwordResetLink ? `
      <div style="background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0;">
        <h3 style="margin-top: 0;">⚠️ Important: Set Your Password</h3>
        <p>Before you can login, you need to set your password. Click the button below:</p>
        <div style="text-align: center; margin: 20px 0;">
          <a href="${passwordResetLink}" style="display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; font-weight: bold;">Set Your Password</a>
        </div>
        <p style="font-size: 12px; color: #666;">This link will expire in 1 hour. If you didn't request this account, please ignore this email.</p>
      </div>
    ` : '';
    
    return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .button { display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }
    .info-box { background: white; padding: 15px; border-left: 4px solid #667eea; margin: 20px 0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Welcome to Abra Travels!</h1>
    </div>
    <div class="content">
      <p>Dear <strong>${name}</strong>,</p>
      
      <p>Great news! Your Abra Travels account has been approved and is ready to use.</p>
      
      ${passwordSection}
      
      <div class="info-box">
        <h3>📋 Your Account Details:</h3>
        <p><strong>Email:</strong> ${email}</p>
        <p><strong>Company:</strong> ${companyName || 'N/A'}</p>
        <p><strong>Status:</strong> Active ✅</p>
      </div>
      
      <p><strong>What's Next?</strong></p>
      <ul>
        <li>${passwordResetLink ? 'Set your password using the link above' : 'Login with your registered email and password'}</li>
        <li>Download the Abra Travels mobile app</li>
        <li>Complete your profile setup</li>
        <li>Start booking trips and managing your travel needs</li>
      </ul>
      
      <p>If you have any questions or need assistance, please don't hesitate to contact our support team.</p>
      
      <p>Welcome aboard!</p>
      
      <p><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>This is an automated message from Abra Travels Management System</p>
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
    `;
  }

  // Plain text version for email clients that don't support HTML
  getApprovalEmailText(name, email, companyName) {
    return `
🎉 Welcome to Abra Travels!

Dear ${name},

Great news! Your Abra Travels account has been approved by our administrator.

You can now login and access all features of our fleet management system.

📋 Your Account Details:
- Email: ${email}
- Company: ${companyName || 'N/A'}
- Status: Active ✅

What's Next?
- Download the Abra Travels mobile app
- Login with your registered email and password
- Complete your profile setup
- Start booking trips and managing your fleet needs

If you have any questions or need assistance, please don't hesitate to contact our support team.

Welcome aboard!

The Abra Travels Team

---
This is an automated message from Abra Travels Management System
© ${new Date().getFullYear()} Abra Travels. All rights reserved.
    `;
  }

  // Send password reset email
  async sendPasswordResetEmail({ email, name, resetLink }) {
    console.log('\n' + '='.repeat(80));
    console.log('📧 EMAIL SERVICE - SEND PASSWORD RESET EMAIL');
    console.log('='.repeat(80));
    console.log('🔹 Recipient Email:', email);
    console.log('🔹 Recipient Name:', name);
    console.log('🔹 Reset Link:', resetLink ? 'YES (provided)' : 'NO');
    console.log('🔹 Timestamp:', new Date().toISOString());
    console.log('-'.repeat(80));
    
    if (!this.initialized || !this.transporter) {
      console.log('❌ FAILED: Email service not initialized');
      console.log('='.repeat(80) + '\n');
      return { success: false, error: 'Email service not configured' };
    }

    const templates = require('./email_templates');

    try {
      const mailOptions = {
        from: `"Abra Travels Support" <${process.env.SMTP_USER}>`,
        to: email,
        subject: '🔐 Reset Your Abra Travels Password',
        html: templates.getPasswordResetTemplate(name, resetLink),
        text: templates.getPasswordResetText(name, resetLink),
      };

      console.log('📤 Sending password reset email via SMTP...');
      const info = await this.transporter.sendMail(mailOptions);
      
      console.log('='.repeat(80));
      console.log('✅ SUCCESS: Password reset email sent!');
      console.log('🔹 Message ID:', info.messageId);
      console.log('🔹 Response:', info.response);
      console.log('🔹 Recipient:', email);
      console.log('='.repeat(80) + '\n');
      
      return { success: true, messageId: info.messageId };
    } catch (error) {
      console.log('='.repeat(80));
      console.log('❌ FAILED: Error sending password reset email');
      console.log('🔹 Error Message:', error.message);
      console.log('🔹 Error Code:', error.code);
      console.log('='.repeat(80) + '\n');
      return { success: false, error: error.message };
    }
  }

  // Send customer rejection email
  async sendCustomerRejectionEmail({ email, name, reason }) {
    if (!this.initialized || !this.transporter) {
      console.warn('⚠️ Email service not initialized. Skipping email notification.');
      return { success: false, error: 'Email service not configured' };
    }

    try {
      const mailOptions = {
        from: `"Abra Travels Support" <${process.env.SMTP_USER}>`,
        to: email,
        subject: 'Abra Travels Account Registration Update',
        html: this.getRejectionEmailTemplate(name, reason),
        text: this.getRejectionEmailText(name, reason),
      };

      const info = await this.transporter.sendMail(mailOptions);
      
      console.log('✅ Rejection email sent to:', email);
      console.log('   Message ID:', info.messageId);
      
      return { success: true, messageId: info.messageId };
    } catch (error) {
      console.error('❌ Failed to send rejection email:', error);
      return { success: false, error: error.message };
    }
  }

  // Generic send email method
  async sendEmail(to, subject, textContent, htmlContent) {
    console.log('\n📧 ========== GENERIC SEND EMAIL ==========');
    console.log('🔹 To:', to);
    console.log('🔹 Subject:', subject);
    console.log('🔹 Initialized:', this.initialized);
    console.log('🔹 Has Transporter:', !!this.transporter);
    
    if (!this.initialized || !this.transporter) {
      console.log('❌ Email service not initialized');
      console.log('🔹 SMTP_USER:', process.env.SMTP_USER ? 'SET' : 'NOT SET');
      console.log('🔹 SMTP_PASSWORD:', process.env.SMTP_PASSWORD ? 'SET' : 'NOT SET');
      throw new Error('Email service not configured. Please set SMTP credentials in .env file');
    }

    try {
      const mailOptions = {
        from: `"Abra Travels Support" <${process.env.SMTP_USER}>`,
        to: to,
        subject: subject,
        text: textContent,
        html: htmlContent,
      };

      console.log('📤 Sending email...');
      const info = await this.transporter.sendMail(mailOptions);
      
      console.log('✅ Email sent successfully!');
      console.log('   Message ID:', info.messageId);
      console.log('   Response:', info.response);
      console.log('========== EMAIL SENT ==========\n');
      
      return { success: true, messageId: info.messageId };
    } catch (error) {
      console.error('❌ Failed to send email:', error.message);
      console.error('   Error code:', error.code);
      console.error('   Error command:', error.command);
      throw error;
    }
  }

  // HTML template for rejection email
  getRejectionEmailTemplate(name, reason) {
    return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: #f44336; color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .info-box { background: white; padding: 15px; border-left: 4px solid #f44336; margin: 20px 0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Abra Travels Registration Update</h1>
    </div>
    <div class="content">
      <p>Dear <strong>${name}</strong>,</p>
      
      <p>Thank you for your interest in Abra Travels.</p>
      
      <p>After reviewing your registration, we regret to inform you that your account application could not be approved at this time.</p>
      
      ${reason ? `
      <div class="info-box">
        <h3>Reason:</h3>
        <p>${reason}</p>
      </div>
      ` : ''}
      
      <p>If you believe this is an error or would like to discuss this decision, please contact our support team.</p>
      
      <p>Thank you for your understanding.</p>
      
      <p><strong>The Abra Travels Team</strong></p>
    </div>
    <div class="footer">
      <p>This is an automated message from Abra Travels Management System</p>
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
    `;
  }

  // Plain text version for rejection email
  getRejectionEmailText(name, reason) {
    return `
Abra Travels Registration Update

Dear ${name},

Thank you for your interest in Abra Travels.

After reviewing your registration, we regret to inform you that your account application could not be approved at this time.

${reason ? `Reason: ${reason}` : ''}

If you believe this is an error or would like to discuss this decision, please contact our support team.

Thank you for your understanding.

The Abra Travels Team

---
This is an automated message from Abra Travels Management System
© ${new Date().getFullYear()} Abra Travels. All rights reserved.
    `;
  }
}

// Export singleton instance
module.exports = new EmailService();
