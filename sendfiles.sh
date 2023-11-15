send_files() {
    read -p 'ip or domain => ' IPIP

    echo "Enter file names (leave blank to send all files), one per line. Press Ctrl+D when done:"
    FILENAMES=""
    while IFS= read -r line; do
        FILENAMES+="$line "
    done

    if [ -z "$FILENAMES" ]; then
        # No file names provided, send all files in the current folder
        echo "Sending all files in the current directory..."
        tar cfzv - * | nc -q 1 ${IPIP} 9
    else
        # File names provided, send only those files
        echo "Sending specified files..."
        tar cfzv - ${FILENAMES} | nc -q 1 ${IPIP} 9
    fi
}

# To use the function, simply call it
send_files

