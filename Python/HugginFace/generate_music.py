from transformers import AutoProcessor, MusicgenForConditionalGeneration
import scipy
import os
from datetime import datetime

def generate_music(prompt, output_dir="generated_beats", max_length_seconds=10):
    """
    Génère un extrait musical à partir d'une description textuelle
    
    Args:
        prompt (str): Description du type de musique à générer
        output_dir (str): Dossier où sauvegarder le fichier audio
        max_length_seconds (int): Durée approximative en secondes
    
    Returns:
        str: Chemin du fichier généré
    """
    # Créer le dossier de sortie s'il n'existe pas
    os.makedirs(output_dir, exist_ok=True)
    
    # Charger le modèle et le processeur
    print("Chargement du modèle MusicGen-Small...")
    processor = AutoProcessor.from_pretrained("facebook/musicgen-large")
    model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-large")
    
    # Calculer le nombre de tokens pour la durée souhaitée (environ 50 tokens par seconde)
    max_new_tokens = int(max_length_seconds * 50)
    
    # Préparer l'entrée
    print(f"Création d'un beat à partir de: '{prompt}'")
    inputs = processor(
        text=[prompt],
        padding=True,
        return_tensors="pt",
    )
    
    # Générer l'audio avec échantillonnage pour plus de diversité
    audio_values = model.generate(
        **inputs, 
        max_new_tokens=max_new_tokens,
        do_sample=True,
        temperature=0.7
    )
    
    # Obtenir le taux d'échantillonnage
    sampling_rate = model.config.audio_encoder.sampling_rate
    
    # Créer un nom de fichier unique basé sur l'horodatage
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"hiphop_beat_{timestamp}.wav"
    filepath = os.path.join(output_dir, filename)
    
    # Sauvegarder le fichier audio
    scipy.io.wavfile.write(
        filepath, 
        rate=sampling_rate, 
        data=audio_values[0, 0].numpy()
    )
    
    print(f"Beat généré et sauvegardé: {filepath}")
    return filepath

if __name__ == "__main__":
    # Exemple de prompt pour un beat hip-hop
    hip_hop_prompt = "Hip hop beat with booming 808 bass, trap hi-hats, and dark piano melody. BPM: 95."
    hip_hop2 = "Hard-hitting Alchemist type beat with dark piano stabs and heavy drums. Menacing minor key piano riff that repeats throughout. Booming 808 bass with extra distortion. Tempo around 75 BPM with trap hi-hats that occasionally double-time. Include subtle brass samples and vinyl crackle for texture. Structure: ominous intro with isolated piano, full beat drops at 4 bars, with occasional drum breaks to highlight the piano melody"
    
    # Générer le beat
    output_file = generate_music(
        prompt=hip_hop2,
        max_length_seconds=20 # Environ 15 secondes
    )