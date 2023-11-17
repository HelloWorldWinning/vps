cat >>~/.bashrc<<EOF
alias sn='sncli'
EOF
cat >~/.snclirci<<EOF
[sncli]
cfg_sn_username = 
cfg_sn_password = 
cfg_sn_password_eval = gpg --quiet --for-your-eyes-only --no-tty --decrypt ~/.sncli-pass.gpg
#kb_edit_note =  enter
#kb_page_down =  enter f
kb_page_up =    command e
clr_note_focus_bg = light blue
cfg_editor = vim

# help https://sncli.readthedocs.io/_/downloads/en/latest/pdf/
# https://github.com/insanum/sncli
EOF

echo "sncli.sh run successfully: sn to use"


