import http.client

host = "192.168.1.7"  # Remplace par l'IP si besoin
try:
    conn = http.client.HTTPSConnection(host, timeout=5)
    conn.request("GET", "/")
    response = conn.getresponse()
    print(f"Réponse : {response.status} {response.reason}")
    conn.close()
except Exception as e:
    print(f"Erreur : {e}")
