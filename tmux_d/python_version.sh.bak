#!/usr/bin/bash
echo $(python_version=$(command -v python >/dev/null 2>&1 && python --version 2>&1 | awk     '{print $2}' || echo ''); conda_env=$(echo $CONDA_DEFAULT_ENV); if [ -z \"$conda_env\" ] && [ -z     \"$python_version\" ]; then echo ''; else echo $conda_env,$python_version; fi)
