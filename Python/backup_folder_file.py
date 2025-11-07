from pathlib import Path
import shutil
import os, sys
import datetime
import time
import subprocess
from datetime import date
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# ================================
# CONFIGURATION - À PERSONNALISER
# ================================
CONFIG = {
    # Configuration Email SMTP
    'smtp': {
        'server': 'smtp.gmail.com',
        'port': 587,
        'sender_email': 'your-email@gmail.com',
        'recipient_email': 'recipient@gmail.com',
        'password': 'your-app-password-here'
    },
    
    # Configuration des chemins
    'paths': {
        'minio_data': '/mnt/minio/data',
        'backup_destination': '/mnt/autre'
    }
}

## Def function send email
def send_email_smtp(sender_email, recipient_email, subject, body, smtp_server, smtp_port, password):
    """
    Envoie un email via SMTP
    """
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

def send_notification_email(subject, body):
    """
    Fonction wrapper pour envoyer des notifications
    """
    smtp_config = CONFIG['smtp']
    send_email_smtp(
        smtp_config['sender_email'],
        smtp_config['recipient_email'],
        subject,
        body,
        smtp_config['server'],
        smtp_config['port'],
        smtp_config['password']
    )

### Date time
current_minute = datetime.now().minute
current_hour = datetime.now().hour
current_day = datetime.now().day
current_month = datetime.now().strftime('%m')
current_year = datetime.now().year

### Paths for MinIO backup
minio_data = CONFIG['paths']['minio_data']
backup_destination = CONFIG['paths']['backup_destination']

# Nom du fichier de sauvegarde avec horodatage
backup_filename = f"minio_backup_{current_year}{str(current_month).zfill(2)}{str(current_day).zfill(2)}_{str(current_hour).zfill(2)}{str(current_minute).zfill(2)}.tar.gz"
backup_full_path = os.path.join(backup_destination, backup_filename)

### Print date time and backup info
print("=" * 60)
print(f"Date du jour: {current_day}/{current_month}/{current_year}")
print(f"Début du backup MinIO à: {current_hour:02d}:{current_minute:02d}")
print("=" * 60)

### Vérifier que le répertoire MinIO existe
if not os.path.exists(minio_data):
    print(f"ERREUR: Le répertoire MinIO {minio_data} n'existe pas!")
    send_notification_email(
        "MinIO Backup - ERREUR",
        f"ERREUR: Répertoire MinIO {minio_data} introuvable!"
    )
    sys.exit(1)

### Vérifier que la destination existe
if not os.path.exists(backup_destination):
    print(f"ERREUR: Le répertoire de destination {backup_destination} n'existe pas!")
    send_notification_email(
        "MinIO Backup - ERREUR",
        f"ERREUR: Répertoire de destination {backup_destination} introuvable!"
    )
    sys.exit(1)

### Backup MinIO à froid (arrêt du service)
print("Arrêt du service MinIO...")
try:
    subprocess.run(['systemctl', 'stop', 'minio'], check=True, capture_output=True, text=True)
    print("Service MinIO arrêté")
    minio_stopped = True
except subprocess.CalledProcessError as e:
    print(f"ATTENTION: Impossible d'arrêter MinIO: {e}")
    print("Backup à chaud (peut causer des incohérences)...")
    minio_stopped = False

### Créer l'archive tar.gz du répertoire MinIO
print(f"Création de l'archive: {backup_full_path}")
try:
    tar_command = ['tar', '-czf', backup_full_path, minio_data]
    result = subprocess.run(tar_command, check=True, capture_output=True, text=True)
    print("Archive créée avec succès")
    backup_success = True

except subprocess.CalledProcessError as e:
    print(f"Erreur lors de la création de l'archive: {e}")
    print(f"STDERR: {e.stderr}")
    backup_success = False

### Redémarrer MinIO si on l'avait arrêté
if minio_stopped:
    print("Redémarrage du service MinIO...")
    try:
        subprocess.run(['systemctl', 'start', 'minio'], check=True, capture_output=True, text=True)
        print("Service MinIO redémarré")
    except subprocess.CalledProcessError as e:
        print(f"ERREUR CRITIQUE: Impossible de redémarrer MinIO: {e}")
        send_notification_email(
            "MinIO Backup - ERREUR CRITIQUE",
            f"ERREUR CRITIQUE: MinIO n'a pas pu être redémarré!\n{e}"
        )

### Vérifier que l'archive a été créée et obtenir sa taille
if backup_success and os.path.exists(backup_full_path):
    backup_size = os.path.getsize(backup_full_path)
    backup_size_mb = backup_size / (1024 * 1024)
    backup_size_gb = backup_size_mb / 1024
    
    print(f"Backup créé: {backup_full_path}")
    
    if backup_size_gb >= 1:
        print(f"Taille: {backup_size_gb:.2f} GB")
        size_display = f"{backup_size_gb:.2f} GB"
    else:
        print(f"Taille: {backup_size_mb:.2f} MB")
        size_display = f"{backup_size_mb:.2f} MB"
    
    # Email de succès
    email_body = f"""Backup MinIO terminé avec succès!

Détails:
- Date: {current_day}/{current_month}/{current_year} à {current_hour:02d}:{current_minute:02d}
- Fichier: {backup_filename}
- Taille: {size_display}
- Source: {minio_data}
- Destination: {backup_full_path}
- Service MinIO: {'Arrêté pendant backup (à froid)' if minio_stopped else 'Backup à chaud'}

Le backup a été créé avec succès."""
    
    send_notification_email("MinIO Backup - Succès", email_body)

else:
    print("ERREUR: Le backup n'a pas pu être créé!")
    send_notification_email(
        "MinIO Backup - ÉCHEC",
        f"Erreur lors de la création du backup MinIO!\nFichier attendu: {backup_full_path}"
    )

print("=" * 60)
print("Script de backup MinIO terminé.")
print("=" * 60)