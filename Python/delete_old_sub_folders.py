import os
import time
import argparse
import shutil

def delete_old_sub_folders(root_folder, days):
    """
    Delete old sub folders more than X days

    Args:
        Path folder (str): ROOT folder where you want to make a clean-up 
        Days (int): X days from /to delete

    How its work : python script.py /path/folder/todelete/ROOT_FOLDER 7 
    """

    seuil_time = time.time() - (days * 24 * 60 * 60)

    for sub_folder in os.listdir(root_folder):
        sub_folder_to_delete = os.path.join(root_folder, sub_folder)

        if os.path.isdir(sub_folder_to_delete):  # Check if sub folder
            if os.path.getmtime(sub_folder_to_delete) < seuil_time:
                try:
                    shutil.rmtree(sub_folder_to_delete)  # Delete all subfolder & contents
                    print ("🔵 Sub folder has been deleted :", sub_folder)
                except OSError as e:
                    print ("⛔ Issue with the process", sub_folder, ":", e)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Delete old sub folders")
    parser.add_argument("root_args", help="Fill the root folder, where you want to delete the sub folder")
    parser.add_argument("days_args", type=int, help="X days from/to delete")

    args = parser.parse_args()

    delete_old_sub_folders(args.root_args, args.days_args)