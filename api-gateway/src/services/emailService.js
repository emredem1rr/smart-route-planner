const nodemailer = require('nodemailer');
require('dotenv').config();

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
  },
});

// Sends password reset code
async function sendResetCode(toEmail, resetCode) {
  const mailOptions = {
    from:    `"Smart Route Planner" <${process.env.GMAIL_USER}>`,
    to:      toEmail,
    subject: 'Şifre Sıfırlama Kodu — Smart Route',
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 480px; margin: auto;">
        <div style="background: #1565C0; padding: 24px; border-radius: 8px 8px 0 0;">
          <h2 style="color: white; margin: 0;">Smart Route Planner</h2>
        </div>
        <div style="background: #f5f7fa; padding: 32px; border-radius: 0 0 8px 8px;">
          <p style="font-size: 16px; color: #424242;">Şifre sıfırlama talebiniz alındı.</p>
          <p style="font-size: 14px; color: #616161;">
            Aşağıdaki kodu uygulamaya girin. Kod <b>15 dakika</b> geçerlidir.
          </p>
          <div style="background: white; border: 2px solid #1565C0;
                      border-radius: 8px; padding: 24px; text-align: center; margin: 24px 0;">
            <span style="font-size: 36px; font-weight: bold;
                         letter-spacing: 8px; color: #1565C0;">
              ${resetCode}
            </span>
          </div>
          <p style="font-size: 12px; color: #9e9e9e;">
            Bu isteği siz yapmadıysanız bu e-postayı görmezden gelin.
          </p>
        </div>
      </div>
    `,
  };
  await transporter.sendMail(mailOptions);
}

// Sends email verification code
async function sendVerificationCode(toEmail, code) {
  const mailOptions = {
    from:    `"Smart Route Planner" <${process.env.GMAIL_USER}>`,
    to:      toEmail,
    subject: 'E-posta Doğrulama Kodu — Smart Route',
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 480px; margin: auto;">
        <div style="background: #1565C0; padding: 24px; border-radius: 8px 8px 0 0;">
          <h2 style="color: white; margin: 0;">Smart Route Planner</h2>
        </div>
        <div style="background: #f5f7fa; padding: 32px; border-radius: 0 0 8px 8px;">
          <p style="font-size: 16px; color: #424242;">
            Hesabınızı doğrulamak için aşağıdaki kodu girin.
          </p>
          <p style="font-size: 14px; color: #616161;">
            Kod <b>15 dakika</b> geçerlidir.
          </p>
          <div style="background: white; border: 2px solid #1565C0;
                      border-radius: 8px; padding: 24px; text-align: center; margin: 24px 0;">
            <span style="font-size: 36px; font-weight: bold;
                         letter-spacing: 8px; color: #1565C0;">
              ${code}
            </span>
          </div>
          <p style="font-size: 12px; color: #9e9e9e;">
            Bu isteği siz yapmadıysanız bu e-postayı görmezden gelin.
          </p>
        </div>
      </div>
    `,
  };
  await transporter.sendMail(mailOptions);
}

module.exports = { sendResetCode, sendVerificationCode };