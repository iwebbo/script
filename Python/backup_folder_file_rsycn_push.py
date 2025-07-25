from pathlib import Path
import shutil
import os, sys
import datetime
import time
import subprocess
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
CONFIG = {
    # Configuration Email SMTP
    'smtp': {
        'server': 'smtp.gmail.com',  # ou smtp.outlook.com, etc.
        'port': 587,
        'sender_email': 'your-email@gmail.com',
        'recipient_email': 'recipient@gmail.com',
        'password': 'your-app-password-here'  # Utilisez un mot de passe d'application
    },
    
    # Configuration des chemins
    'paths': {
        'jenkins_home': '/var/lib/jenkins/',
        'backup_base_path': '/tmp/backups/jenkins/',
        'rsync_destination': 'user@backup-server:/path/to/backup/jenkins/',
        'ssh_key_path': '~/.ssh/id_rsa'  # Chemin vers votre clé SSH privée
    },
    
    # Configuration du backup
    'backup': {
        'exclude_patterns': [
            'workspace/*/target',  # Exclure les builds Maven/Gradle
            'logs/*',              # Exclure les anciens logs
            '**/target',           # Exclure tous les dossiers target
            '**/*.log'             # Exclure les fichiers log
        ]
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
current_second = datetime.now().second
current_minute = datetime.now().minute
current_hour = datetime.now().hour
current_day = datetime.now().day
current_month = datetime.now().strftime('%m')
current_year = datetime.now().year
date = datetime.now().replace(microsecond=0).isoformat()

### Paths for Jenkins backup
jenkins_home = CONFIG['paths']['jenkins_home']
backup_base_path = CONFIG['paths']['backup_base_path']
backup_date_folder = f"{current_year}/{str(current_month).zfill(2)}/{str(current_day).zfill(2)}"
backup_destination = os.path.join(backup_base_path, backup_date_folder)

# Nom du fichier de sauvegarde avec horodatage
backup_filename = f"jenkins_backup_{current_year}{str(current_month).zfill(2)}{str(current_day).zfill(2)}_{str(current_hour).zfill(2)}{str(current_minute).zfill(2)}.tar.gz"
backup_full_path = os.path.join(backup_destination, backup_filename)

### Créer le répertoire de destination si nécessaire
if not os.path.exists(backup_destination):
    os.makedirs(backup_destination)
    print(f"Dossier créé: {backup_destination}")
else:
    print(f"Dossier existe déjà: {backup_destination}")

### Print date time and backup info
print(f"Date du jour: {current_day}/{current_month}/{current_year}")
print(f"Début du backup Jenkins à: {current_hour:02d}:{current_minute:02d}")

### Vérifier que Jenkins Home existe
if not os.path.exists(jenkins_home):
    print(f"ERREUR: Le répertoire Jenkins {jenkins_home} n'existe pas!")
    send_notification_email(
        "Jenkins Backup - ERREUR",
        f"ERREUR: Répertoire Jenkins {jenkins_home} introuvable!"
    )
    sys.exit(1)

### Backup Jenkins à chaud (sans arrêt du service)
print("Backup Jenkins à chaud...")

### Créer l'archive tar.gz du répertoire Jenkins
print(f"Création de l'archive: {backup_full_path}")
try:
    # Construire la commande tar avec les exclusions
    tar_command = ['tar', '-czf', backup_full_path]
    
    # Ajouter les patterns d'exclusion
    for pattern in CONFIG['backup']['exclude_patterns']:
        tar_command.extend(['--exclude', pattern])
    
    # Ajouter le répertoire source
    tar_command.append(jenkins_home)

    result = subprocess.run(tar_command, check=True, capture_output=True, text=True)
    print("Archive créée avec succès")
    backup_success = True

except subprocess.CalledProcessError as e:
    print(f"Erreur lors de la création de l'archive: {e}")
    print(f"STDERR: {e.stderr}")
    backup_success = False

### Vérifier que l'archive a été créée et obtenir sa taille
if backup_success and os.path.exists(backup_full_path):
    backup_size = os.path.getsize(backup_full_path)
    backup_size_mb = backup_size / (1024 * 1024)
    print(f"Backup créé: {backup_full_path}")
    print(f"Taille: {backup_size_mb:.2f} MB")
    
    ### Commande rsync vers serveur de backup
    rsync_command = [
        'rsync', 
        '-avz', 
        '--progress',
        '-e', f'ssh -i {CONFIG["paths"]["ssh_key_path"]}',
        backup_full_path,
        CONFIG['paths']['rsync_destination']
    ]
    
    print("Synchronisation vers serveur de backup...")
    try:
        result = subprocess.run(rsync_command, check=True, capture_output=True, text=True)
        print("Rsync terminé avec succès")
        rsync_success = True
    except subprocess.CalledProcessError as e:
        print(f"Erreur lors du rsync: {e}")
        print(f"STDERR: {e.stderr}")
        rsync_success = False
    
    # Email de succès
    if rsync_success:
        email_body = f"""Backup Jenkins terminé avec succès!

Détails:
- Date: {current_day}/{current_month}/{current_year} à {current_hour:02d}:{current_minute:02d}
- Fichier: {backup_filename}
- Taille: {backup_size_mb:.2f} MB
- Source: {jenkins_home}
- Destination locale: {backup_full_path}
- Synchronisé vers serveur de backup: OUI

Le backup a été créé et synchronisé avec succès."""
        
        send_notification_email("Jenkins Backup - Succès", email_body)
        
        # Nettoyer le fichier local après synchronisation réussie
        try:
            os.remove(backup_full_path)
            print(f"Fichier local supprimé: {backup_full_path}")
        except OSError as e:
            print(f"Erreur lors de la suppression du fichier local: {e}")
    else:
        # Email si rsync échoue
        email_body = f"""Backup Jenkins créé mais erreur lors de la synchronisation!

Détails:
- Date: {current_day}/{current_month}/{current_year} à {current_hour:02d}:{current_minute:02d}
- Fichier: {backup_filename}
- Taille: {backup_size_mb:.2f} MB
- Destination locale: {backup_full_path}
- Synchronisé vers serveur de backup: ÉCHEC

Le backup local existe mais n'a pas pu être synchronisé."""

        send_notification_email("Jenkins Backup - Erreur Rsync", email_body)
        
        # Garder le fichier local en cas d'échec du rsync pour retry manuel
        print(f"Fichier local conservé pour retry manuel: {backup_full_path}")

else:
    print("ERREUR: Le backup n'a pas pu être créé!")
    send_notification_email(
        "Jenkins Backup - ÉCHEC",
        f"Erreur lors de la création du backup Jenkins!\nFichier attendu: {backup_full_path}"
    )

print("Script de backup Jenkins terminé.")