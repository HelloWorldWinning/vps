#! /usr/bin/python3

# 在使用这个插件之前你需要先安装以下程序
# 压缩文件：atool unrar unzip p7zip-full
# 网页文件：w3m
# 种子文件：transmission
# 文本文件：bat

import os
import sys


def path_transfer(path_input):
    rg_list = path_input.split(':')
    if len(rg_list) == 1:
        bat_range = 0
    else:
        bat_range = rg_list[1].replace('\n', '')
    file_path_list = rg_list[0].replace('\n', '').split('/')
    for i, filep in zip(range(len(file_path_list)), file_path_list):
        path_space = filep.find(' ')
        if not path_space == -1:
            file_path_list[i] = "'{}'".format(filep)
        file_path = '/'.join(file_path_list)
    preview_nameandline = [file_path, bat_range]
    return preview_nameandline


if __name__ == "__main__":
    path_input = sys.stdin.readlines()[0]
    if path_input == None:
        path_input = sys.argv[1]
    preview_nameandline = path_transfer(path_input)
    if os.path.isdir(preview_nameandline[0]):
        os.system('ls -la {}'.format(preview_nameandline[0]))
    elif preview_nameandline[0].replace("'", '').endswith(('.zip', '.ZIP', '.tar', '.tar.gz', 'rar', '7z', 'RAR')):
        os.system('als {}'.format(preview_nameandline[0]))
    elif preview_nameandline[0].replace("'", '').endswith('.torrent'):
        os.system('transmission-show {}'.format(preview_nameandline[0]))
    elif preview_nameandline[0].replace("'", '').endswith(('.html', '.htm', '.xhtml')):
        os.system('w3m -dump {}'.format(preview_nameandline[0]))
    # elif preview_nameandline[0].replace("'", '').endswith(('.png')):
        # os.system('img2txt {}'.format(preview_nameandline[0]))
    elif os.path.exists(preview_nameandline[0]):
        os.system('bat --style=numbers --color=always -r {}: {}'.format(
            preview_nameandline[1], preview_nameandline[0]))
    else:
        os.system('echo {}'.format(preview_nameandline[0]))
