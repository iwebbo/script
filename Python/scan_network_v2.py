import socket
import threading
from queue import Queue

def portscan(target, port):
    """Scanne un port spécifique sur une cible donnée."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)  # Ajout d'un timeout pour éviter le blocage
        sock.connect((target, port))
        return True
    except:
        return False

def scan_ip(ip_address, ports):
    """Scanne les ports sur une adresse IP donnée."""
    open_ports = []
    queue = Queue()

    for port in ports:
        queue.put(port)

    thread_list = []
    for _ in range(1000):  # Nombre de threads ajustables
        thread = threading.Thread(target=lambda: executor(queue, ip_address, open_ports))
        thread_list.append(thread)

    for thread in thread_list:
        thread.start()
    for thread in thread_list:
        thread.join()
    
    if open_ports:
      print(f"Ports ouverts sur {ip_address}: {open_ports}")
    else:
      print(f"Aucun port ouvert détecté sur {ip_address}")
    return open_ports #retourne la liste des ports ouverts

def executor(queue, ip_address, open_ports):
    """Exécute le scan des ports depuis la file d'attente."""
    while not queue.empty():
        port = queue.get()
        if portscan(ip_address, port):
            open_ports.append(port)

def scan_network(start_ip, end_ip, ports):
    """Scanne toutes les adresses IP dans une plage donnée."""
    start_ip_parts = list(map(int, start_ip.split('.')))
    end_ip_parts = list(map(int, end_ip.split('.')))

    current_ip_parts = start_ip_parts[:]  # Copie de la liste
    
    while current_ip_parts <= end_ip_parts:
        ip_address = ".".join(map(str, current_ip_parts))
        scan_ip(ip_address, ports)

        # Incrémentation de l'adresse IP
        current_ip_parts[-1] += 1
        for i in range(len(current_ip_parts) - 1, 0, -1):
            if current_ip_parts[i] > 255:
                current_ip_parts[i] = 0
                current_ip_parts[i - 1] += 1
        if current_ip_parts[-1] > 255:
           current_ip_parts[-2] +=1
           current_ip_parts[-1] = 1
        if current_ip_parts[-2] > 255:
           current_ip_parts[-3] +=1
           current_ip_parts[-2] = 1

if __name__ == "__main__":
    start_ip = "192.168.1.1"
    end_ip = "192.168.1.254"
    ports_to_scan = range(1, 10000)  # Ports à scanner (modifiable)

    scan_network(start_ip, end_ip, ports_to_scan)