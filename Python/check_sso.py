import http.client
import urllib.parse

# Configuration
GRAFANA_HOST = "your-grafana-instance.com"  # Nom du serveur Grafana
GRAFANA_LOGIN_PATH = "/login"  # URL de connexion
GRAFANA_TEST_PAGE = "/dashboard/home"  # Page test après connexion (à modifier selon votre setup)
LDAP_USERNAME = "your-ldap-username"
LDAP_PASSWORD = "your-ldap-password"

# Fonction d'authentification
def authenticate():
    print("Tentative d'authentification via SSO...")

    conn = http.client.HTTPSConnection(GRAFANA_HOST)
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    payload = urllib.parse.urlencode({"user": LDAP_USERNAME, "password": LDAP_PASSWORD})

    conn.request("POST", GRAFANA_LOGIN_PATH, body=payload, headers=headers)
    response = conn.getresponse()
    cookies = response.getheader("Set-Cookie")  # Récupération du cookie de session
    conn.close()

    if response.status == 200 and cookies:
        print("✅ Authentification réussie. Cookie récupéré.")
        return cookies
    else:
        print(f"❌ Échec de l'authentification (Code {response.status}) : {response.reason}")
        return None

# Vérification de l'accès à une page interne protégée
def test_authenticated_page(cookies):
    print("Vérification de l'accès à une page interne protégée...")

    conn = http.client.HTTPSConnection(GRAFANA_HOST)
    headers = {
        "Cookie": cookies,
        "User-Agent": "Mozilla/5.0"
    }

    conn.request("GET", GRAFANA_TEST_PAGE, headers=headers)
    response = conn.getresponse()
    conn.close()

    if response.status == 200:
        print(f"✅ Accès confirmé à {GRAFANA_TEST_PAGE}")
        print(f"ℹ️ URL complète après connexion : https://{GRAFANA_HOST}{GRAFANA_TEST_PAGE}")
    else:
        print(f"❌ Accès refusé à {GRAFANA_TEST_PAGE} (Code {response.status}) : {response.reason}")

# Exécution du script
if __name__ == "__main__":
    cookies = authenticate()
    if cookies:
        test_authenticated_page(cookies)
