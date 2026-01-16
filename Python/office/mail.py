import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
import os
from config import CONFIG_ALARM_EMAIL

class GmailService(object):
    def __init__(self, username=None, password=None):
        self.username = username
        self.password = password

    def send(self, to, subject, body, attachments=None):
        msg = MIMEMultipart()
        msg['From'] = self.username
        msg['To'] = to
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'plain'))

        if attachments:
            for file_path in attachments:
                part = MIMEBase('application', 'octet-stream')
                with open(file_path, 'rb') as f:
                    part.set_payload(f.read())
                encoders.encode_base64(part)
                if '\\' in file_path:
                    part.add_header('Content-Disposition', f'attachment; filename={file_path.split("\\")[-1]}')
                else:
                    part.add_header('Content-Disposition', f'attachment; filename={file_path.split("/")[-1]}')
                msg.attach(part)

        with smtplib.SMTP('smtp.gmail.com', 587) as server:
            server.starttls()
            server.login(self.username, self.password)
            server.sendmail(self.username, to, msg.as_string())


class AlarmEmail(GmailService):
    def __init__(self):
        username = CONFIG_ALARM_EMAIL.username
        password = os.getenv(CONFIG_ALARM_EMAIL.env)
        super().__init__(username=username, password=password)

if __name__ == "__main__":
    # Example usage
    # Send a warning email to same address. Attach the current script as an attachment
    email = AlarmEmail()
    try:
        email.send(email.username + '@gmail.com',
                    'Test Email',
                    'This is a test email sent from Python.',
                   [__file__])
        print("Email sent successfully!")
    except Exception as e:
        print(f"Failed to send email: {e}")
