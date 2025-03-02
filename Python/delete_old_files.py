import os
import time
import argparse

def delete_old_files(path_folder, days):
    """
    Delete old file more than X days

    Args:
        Path folder (str): Path folder where you want to make a clean-up 
        Days (int): X days from /to delete

    How its work : python script.py /path/folder/todelete/oldfiles 7 
    """

    seuil_time = time.time() - (days * 24 * 60 * 60)  # Calcul du seuil de temps en secondes

    for file_name in os.listdir(path_folder):
        path_filename = os.path.join(path_folder, file_name)

        # Vérifier si c'est un fichier et s'il est plus ancien que le seuil
        if os.path.isfile(path_filename) and os.path.getmtime(path_filename) < seuil_time:
            try:
                os.remove(path_filename)
                print ("🔵 Fichier supprimé :", file_name)
            except OSError as e:
                print ("⛔ Issue with the process", file_name, ":", e)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Delete old files from X days")
    parser.add_argument("path_folder", help="Your path folder of old files need to be delete")
    parser.add_argument("days", type=int, help="X days need to be keep")

    args = parser.parse_args()

    delete_old_files(args.path_folder, args.days) 