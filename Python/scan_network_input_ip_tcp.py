import socket
import threading
from queue import Queue

target = input(" Entrer l’adresse IP de la cible : ")
queue = Queue()
open_ports = []

def portscan(port):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((target, port))
        return True
    except:
        return False
    
def fill_queue(port_list):
    for port in port_list:
        queue.put(port)
def executor():
    while not queue.empty():
        port = queue.get()
        if portscan(port):
            print(" Le port {} est ouvert".format(port))
            open_ports.append(port)

port_list = range(1, 10000)
fill_queue(port_list)
thread_list = []

for t in range(500):
    thread = threading.Thread(target=executor)
    thread_list.append(thread)
for thread in thread_list:
    thread.start()
for thread in thread_list:
    thread.join()
print( "Les ports ouverts sont : " , open_ports )