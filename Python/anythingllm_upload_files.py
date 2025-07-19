"""
Copyright (c) 2025 [A&E Coding]

Permission est accordée, gratuitement, à toute personne obtenant une copie
 de ce logiciel et des fichiers de documentation associés (le "upload_anythingllm.py"),
 de traiter le Logiciel sans restriction, y compris, sans s'y limiter, les droits
 d'utiliser, de copier, de modifier, de fusionner, de publier, de distribuer, de sous-licencier,
 et/ou de vendre des copies du Logiciel, et de permettre aux personnes à qui
 le Logiciel est fourni de le faire, sous réserve des conditions suivantes :

Le texte ci-dessus et cette autorisation doivent être inclus dans toutes les copies
 ou portions substantielles du Logiciel.

LE LOGICIEL EST FOURNI "TEL QUEL", SANS GARANTIE D'AUCUNE SORTE, EXPLICITE OU IMPLICITE,
Y COMPRIS MAIS SANS S'Y LIMITER, LES GARANTIES DE QUALITÉ MARCHANDE, D'ADÉQUATION
À UN USAGE PARTICULIER ET D'ABSENCE DE CONTREFAÇON. EN AUCUN CAS LES AUTEURS OU TITULAIRES
DU COPYRIGHT NE POURRONT ÊTRE TENUS RESPONSABLES DE TOUTE RÉCLAMATION, DOMMAGE OU AUTRE RESPONSABILITÉ,
QUE CE SOIT DANS UNE ACTION CONTRACTUELLE, DÉLICTUELLE OU AUTRE, DÉCOULANT DE,
OU EN RELATION AVEC LE LOGICIEL OU L'UTILISATION OU D'AUTRES INTERACTIONS AVEC LE LOGICIEL.
"""

import os
import json
import requests
import argparse
import mimetypes
from pathlib import Path

# 🔧 CONFIGURATION PAR DÉFAUT
ANYTHINGLLM_API_URL = "http://localhost:3001/api/v1"
ANYTHINGLLM_API_KEY = "0M6D0DJ-QVDMFQB-KNZMBH3-16F5KXH"
DOCUMENT_FOLDER_NAME = "Crewai"  # Nom du dossier par défaut
ROOT_FOLDER = "files"  # Dossier contenant les fichiers à uploader par défaut

# Types de fichiers supportés par AnythingLLM
SUPPORTED_EXTENSIONS = {
    # Documents texte
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.csv': 'text/csv',
    '.json': 'application/json',
    
    # Documents Microsoft
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    
    # Code source
    '.py': 'text/x-python',
    '.js': 'text/javascript',
    '.java': 'text/x-java',
    '.c': 'text/x-c',
    '.cpp': 'text/x-c++',
    '.html': 'text/html',
    '.css': 'text/css',
    
    # PDF
    '.pdf': 'application/pdf',
    
    # Archives
    '.zip': 'application/zip',
    
    # Images
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    
    # Autres
    '.log': 'text/plain',
    '.xml': 'application/xml',
    '.yaml': 'application/x-yaml',
    '.yml': 'application/x-yaml',
}

class AnythingLLMUploader:
    def __init__(self, api_url, api_key, folder_name):
        self.api_url = api_url
        self.api_key = api_key
        self.folder_name = folder_name
        self.headers = {"Authorization": f"Bearer {self.api_key}"}
        
        # Initialiser mimetypes
        mimetypes.init()
        
        # Ajouter des types MIME supplémentaires pour améliorer la détection
        for ext, mime in SUPPORTED_EXTENSIONS.items():
            mimetypes.add_type(mime, ext)
    
    def create_or_verify_folder(self):
        """
        Vérifie si le dossier existe, sinon le crée.
        """
        print(f"🔍 Vérification du dossier '{self.folder_name}'...")

        # Vérification de l'existence du dossier
        check_response = requests.get(
            f"{self.api_url}/documents/folder/{self.folder_name}", 
            headers=self.headers
        )

        if check_response.status_code == 200:
            print(f"✅ Dossier '{self.folder_name}' déjà existant.")
            return True

        # Création du dossier s'il n'existe pas
        print(f"🚀 Création du dossier '{self.folder_name}'...")
        create_response = requests.post(
            f"{self.api_url}/document/create-folder",
            json={"name": self.folder_name},
            headers=self.headers,
        )

        if create_response.status_code == 200:
            print(f"✅ Dossier '{self.folder_name}' créé avec succès !")
            return True
        else:
            print(f"❌ Erreur lors de la création du dossier : {create_response.text}")
            return False
    
    def get_mimetype(self, filepath):
        """
        Détermine le type MIME d'un fichier en utilisant l'extension.
        Méthode simplifiée compatible avec Windows, sans dépendance externe.
        """
        # D'abord vérifier par extension dans notre dictionnaire
        ext = os.path.splitext(filepath)[1].lower()
        if ext in SUPPORTED_EXTENSIONS:
            return SUPPORTED_EXTENSIONS[ext]
        
        # Sinon, utiliser mimetypes standard
        mime_type, _ = mimetypes.guess_type(filepath)
        
        # Valeur par défaut si non reconnu
        return mime_type or 'application/octet-stream'
    
    def is_supported_file(self, filepath):
        """
        Vérifie si le fichier est d'un type pris en charge.
        """
        ext = os.path.splitext(filepath)[1].lower()
        return ext in SUPPORTED_EXTENSIONS
    
    def is_binary_file(self, filepath):
        """
        Essaie de déterminer si un fichier est binaire ou texte.
        """
        ext = os.path.splitext(filepath)[1].lower()
        binary_extensions = ['.pdf', '.docx', '.xlsx', '.pptx', '.zip', '.jpg', '.jpeg', '.png', '.gif']
        
        # Si l'extension est connue comme binaire
        if ext in binary_extensions:
            return True
            
        # Pour les extensions inconnues, essayer de lire le début du fichier
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                f.read(1024)  # Essayer de lire comme texte
            return False  # Si réussi, c'est probablement du texte
        except UnicodeDecodeError:
            return True  # Si échec, c'est probablement binaire
    
    def upload_json_file(self, filepath):
        """
        Upload un fichier JSON avec traitement spécifique.
        """
        filename = os.path.basename(filepath)
        
        try:
            with open(filepath, "r", encoding="utf-8") as file:
                json_data = json.load(file)  # Charger le JSON
            
            # Pour les JSON, on envoie les données au format JSON
            upload_url = f"{self.api_url}/document/upload/{self.folder_name}"
            files = {"file": (filename, json.dumps(json_data, ensure_ascii=False))}
            
            response = requests.post(upload_url, files=files, headers=self.headers)
            
            if response.status_code == 200:
                print(f"✅ {filename} uploadé avec succès dans '{self.folder_name}' !")
                return True
            else:
                print(f"❌ Échec de l'upload de {filename} : {response.text}")
                return False
        except json.JSONDecodeError:
            print(f"⚠️ {filename} n'est pas un fichier JSON valide, tentative d'upload comme fichier texte...")
            return self.upload_regular_file(filepath)
        except Exception as e:
            print(f"❌ Erreur lors du traitement de {filename} : {str(e)}")
            return False
    
    def upload_regular_file(self, filepath):
        """
        Upload un fichier standard (non-JSON).
        """
        filename = os.path.basename(filepath)
        mimetype = self.get_mimetype(filepath)
        
        upload_url = f"{self.api_url}/document/upload/{self.folder_name}"
        
        try:
            # Déterminer le mode d'ouverture du fichier (binaire ou texte)
            mode = "rb" if self.is_binary_file(filepath) else "r"
            
            with open(filepath, mode) as f:
                if mode == "r":
                    # Pour les fichiers texte, éviter les problèmes d'encodage en lisant manuellement
                    content = f.read()
                    files = {"file": (filename, content, mimetype)}
                else:
                    # Pour les fichiers binaires
                    files = {"file": (filename, f, mimetype)}
                
                response = requests.post(upload_url, files=files, headers=self.headers)
            
            if response.status_code == 200:
                print(f"✅ {filename} ({mimetype}) uploadé avec succès dans '{self.folder_name}' !")
                return True
            else:
                print(f"❌ Échec de l'upload de {filename} : {response.text}")
                return False
        except Exception as e:
            print(f"❌ Erreur lors de l'upload de {filename} : {str(e)}")
            return False
    
    def upload_file(self, filepath):
        """
        Upload un fichier vers AnythingLLM.
        Détermine la méthode d'upload en fonction du type de fichier.
        """
        if not os.path.exists(filepath):
            print(f"❌ Le fichier {filepath} n'existe pas.")
            return False
        
        if not self.is_supported_file(filepath):
            print(f"⚠️ Le fichier {filepath} a une extension non reconnue. L'upload pourrait échouer.")
        
        ext = os.path.splitext(filepath)[1].lower()
        if ext == '.json':
            return self.upload_json_file(filepath)
        else:
            return self.upload_regular_file(filepath)
    
    def find_files_to_upload(self, root_folder, extensions=None):
        """
        Recherche récursivement tous les fichiers à uploader dans le dossier et ses sous-dossiers.
        Peut filtrer par extensions si spécifié.
        """
        files_to_upload = []
        
        for root, _, files in os.walk(root_folder):
            for file in files:
                filepath = os.path.join(root, file)
                
                # Si extensions est spécifié, filtrer par extension
                if extensions:
                    ext = os.path.splitext(file)[1].lower()
                    if ext in extensions:
                        files_to_upload.append(filepath)
                else:
                    # Sinon prendre tous les fichiers avec extensions supportées
                    if self.is_supported_file(filepath):
                        files_to_upload.append(filepath)
        
        return files_to_upload
    
    def upload_files_from_folder(self, root_folder, extensions=None):
        """
        Upload tous les fichiers d'un dossier vers AnythingLLM.
        """
        if not os.path.exists(root_folder):
            print(f"❌ Erreur : Le dossier '{root_folder}' n'existe pas.")
            return 0
        
        files_to_upload = self.find_files_to_upload(root_folder, extensions)
        
        if not files_to_upload:
            print(f"⚠️ Aucun fichier compatible trouvé dans '{root_folder}'.")
            return 0
        
        print(f"🔍 {len(files_to_upload)} fichiers trouvés à uploader.")
        
        successful_uploads = 0
        for filepath in files_to_upload:
            if self.upload_file(filepath):
                successful_uploads += 1
        
        return successful_uploads


def main():
    # Parsing des arguments en ligne de commande
    parser = argparse.ArgumentParser(description="Upload des fichiers vers AnythingLLM")
    parser.add_argument("--url", default=ANYTHINGLLM_API_URL, help="URL de l'API AnythingLLM")
    parser.add_argument("--key", default=ANYTHINGLLM_API_KEY, help="Clé API AnythingLLM")
    parser.add_argument("--folder", default=DOCUMENT_FOLDER_NAME, help="Nom du dossier de destination dans AnythingLLM")
    parser.add_argument("--source", default=ROOT_FOLDER, help="Dossier source contenant les fichiers à uploader")
    parser.add_argument("--file", help="Chemin d'un fichier spécifique à uploader (prioritaire sur --source)")
    parser.add_argument("--extensions", nargs="+", help="Liste d'extensions à uploader (ex: .py .pdf .txt)")
    
    args = parser.parse_args()
    
    # Convertir les extensions en liste de formats corrects
    extensions_filter = None
    if args.extensions:
        extensions_filter = [ext if ext.startswith('.') else f'.{ext}' for ext in args.extensions]
        print(f"🔍 Filtrage activé pour les extensions: {', '.join(extensions_filter)}")
    
    # Création de l'uploader
    uploader = AnythingLLMUploader(args.url, args.key, args.folder)
    
    if uploader.create_or_verify_folder():
        if args.file:
            # Upload d'un fichier spécifique
            filepath = args.file
            print(f"🚀 Upload du fichier: {filepath}")
            if uploader.upload_file(filepath):
                print(f"\n✅ Fichier '{os.path.basename(filepath)}' uploadé avec succès !")
            else:
                print(f"\n❌ Échec de l'upload du fichier '{os.path.basename(filepath)}'")
        else:
            # Upload des fichiers d'un dossier
            print(f"🚀 Recherche des fichiers dans: {args.source}")
            total_uploaded = uploader.upload_files_from_folder(args.source, extensions_filter)
            print(f"\n🎯 {total_uploaded} fichiers envoyés dans '{args.folder}' sur AnythingLLM !")


# 🚀 Exécution du script
if __name__ == "__main__":
    main()