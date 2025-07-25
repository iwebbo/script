from pathlib import Path
import shutil
import os, sys
import datetime
import time
from datetime import date
from datetime import datetime, timedelta
import pandas as pd
import glob
from dateutil import parser
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# ================================
# CONFIGURATION - À PERSONNALISER
# ================================
# Email SMTP
SENDER_EMAIL = "your-email@gmail.com"
RECIPIENT_EMAIL = "recipient@gmail.com"
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
SMTP_PASSWORD = "your-app-password-here"

# Chemins
PATH_SRC_BASE = '/srv/ftp/Camera/'
PATH_DST_BASE = '/backup/Camera/'
CAMERA_NAME = "Kitchen"  # Pour les emails

## Def function send email
def send_email_smtp(sender_email, recipient_email, subject, body, smtp_server, smtp_port, password):
    try:
        # Create MIME message
        msg = MIMEMultipart()
        msg['From'] = sender_email
        msg['To'] = recipient_email
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'plain'))
        # Connect to SMTP server
        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.starttls()  # Secure connection
            server.login(sender_email, password)
            server.sendmail(sender_email, recipient_email, msg.as_string())
            print("Email sent successfully!")
    except Exception as e:
        print(f"An error occurred: {e}")

### Date time
current_second = datetime.now().second
current_minute = datetime.now().minute
current_hour = datetime.now().hour
current_day = datetime.now().day
current_month = datetime.now().strftime('%m')
current_year = datetime.now().year
date = datetime.now().replace(microsecond=0).isoformat()

###Path source & Destination
path_src = PATH_SRC_BASE
path_dst = PATH_DST_BASE
src = path_src + str(current_year).zfill(4) + '/' + str(current_month).zfill(2) + '/'  + str(current_day).zfill(2)
dst = path_dst + str(current_year).zfill(4) + '/' + str(current_month).zfill(2) + '/' + str(current_day).zfill(2)
directory = dst
if not os.path.exists(directory):
    os.makedirs(directory)
    print("Folder has been created " + dst)
else:
    print ("Folder already exists " + dst)

###Print date time and date time need to be backup
print ("Date of day " + str(current_day) + str(current_month) + str(current_year))
files_src = os.listdir(src)
if files_src is not None:
    print (" Backup will be proceed")
else:
    print (" Not source folder directory, no backup")

### Loop for X files find
for all_file in files_src:
    print (all_file)
    shutil.copy2(os.path.join(src,all_file), dst)

### Check present files backups, if backup was done
path_to_check = dst + '/*.mp4'
check_file = glob.glob(path_to_check)
print ("Path dest to check: " + path_to_check)
if check_file:
    print ("Files has been copy")
    shutil.rmtree(src)
    send_email_smtp(SENDER_EMAIL, RECIPIENT_EMAIL, f"Camera Backup - {CAMERA_NAME}", f"Backup {CAMERA_NAME} - done", SMTP_SERVER, SMTP_PORT, SMTP_PASSWORD)
else:
    print ("Files hasn't been copied ! ")
    send_email_smtp(SENDER_EMAIL, RECIPIENT_EMAIL, f"Camera Backup - {CAMERA_NAME}", f"Backup {CAMERA_NAME} - issue!", SMTP_SERVER, SMTP_PORT, SMTP_PASSWORD)