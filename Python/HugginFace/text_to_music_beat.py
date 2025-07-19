from transformers import AutoProcessor, MusicgenForConditionalGeneration
import scipy
import uuid

# Charger le modèle et le processeur
processor = AutoProcessor.from_pretrained("facebook/musicgen-medium")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-medium")

# Créer votre prompt
prompt = "Hip hop beat with deep bass, crisp snares, and a catchy melody. BPM: 95"

# Préparer l'entrée
inputs = processor(
    text=[prompt],
    padding=True,
    return_tensors="pt",
)

# Générer l'audio (vous pouvez ajuster max_new_tokens pour contrôler la durée)
audio_values = model.generate(**inputs, max_new_tokens=500)

# Obtenir le taux d'échantillonnage du modèle
sampling_rate = model.config.audio_encoder.sampling_rate

# Enregistrer le fichier audio
output_filename = f"generated_beat_{uuid.uuid4()}.wav"
scipy.io.wavfile.write(output_filename, rate=sampling_rate, data=audio_values[0, 0].numpy())