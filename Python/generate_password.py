import secrets
import string
def generate_secure_password(length=25):
    # Définition des jeux de caractères
    lowercase = string.ascii_lowercase
    uppercase = string.ascii_uppercase
    digits = string.digits
    special_chars = '!@#$%^&*()_+-=[]|;:,.<>?'
    # Combinaison de tous les caractères
    all_chars = lowercase + uppercase + digits + special_chars

    # Générer un mot de passe aléatoire sécurisé
    password = [
        secrets.choice(lowercase),
        secrets.choice(uppercase),
        secrets.choice(digits),
        secrets.choice(special_chars)
    ]

    # Remplir le reste du mot de passe avec des caractères aléatoires
    for _ in range(length - 4):
        password.append(secrets.choice(all_chars))

    # Mélanger le mot de passe de manière aléatoire
    secrets.SystemRandom().shuffle(password)

    # Convertir la liste en chaîne de caractères
    return ''.join(password)

print("Mot de passe généré :", generate_secure_password())