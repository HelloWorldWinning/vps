import os
import concurrent.futures
import subprocess

current_working_directory = os.getcwd()

all_entries = os.listdir(current_working_directory)


md_files = [i for i in all_entries if i.endswith(".md") or i.endswith(".markdown")]
html_files_no_end = [i.rsplit(".",1)[0] for i in all_entries if i.endswith(".html") or i.endswith(".htm")]

new_md_files=[i for i in md_files if i.rsplit(".",1)[0] not in html_files_no_end]

if not  new_md_files :
    print("\n\n\n ======== Nothing New ========\n\n\n")
#    return None
exit()


def md_to_html(md_file_name):
    html_name = md_file_name.rsplit(".",1)[0]+".html"
   #result = subprocess.run(["pandoc", "-s", input_file, "-o", output_file], capture_output=True, text=True)
    result = subprocess.run(['pandoc', '-s',md_file_name,'-o',html_name], stdout=subprocess.PIPE)
    print(result.stdout.decode('utf-8'))

# Using ThreadPoolExecutor to run the function in parallel
with concurrent.futures.ThreadPoolExecutor() as executor:
    results = list(executor.map(md_to_html,new_md_files))
