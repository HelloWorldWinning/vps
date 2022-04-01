
jupyter notebook --generate-config
  
cat >> /root/.jupyter/jupyter_notebook_config.py <<EOF 

c.NotebookApp.allow_remote_access = True        #允许远程连接
c.NotebookApp.open_browser = False              # 禁止自动打开浏览器
c.NotebookApp.port =8888                        #任意指定一个端口
c.NotebookApp.ip = '0.0.0.0' # listen on all IPs
c.NotebookApp.allow_root= True
#c.NotebookApp.ip='*'                            # 设置所有ip皆可访问
#c.NotebookApp.password = u'sha1:.......'        #之前复制的密码

EOF


jupyter notebook password 

 
