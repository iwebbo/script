import http.client

host = "instance-grafana.com"  # Remplace par le vrai domaine
login_path = "/login"  # Modifier si la redirection donne une autre URL

conn = http.client.HTTPSConnection(host)
conn.request("GET", login_path)
response = conn.getresponse()

print(f"Code HTTP : {response.status}")
print(response.read().decode())

conn.close()
