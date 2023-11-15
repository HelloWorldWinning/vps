read -p 'ip or domain => ' IPIP
echo "Enter file names (one per line), followed by an empty line to end:"

# Reading file names into an array
filelist=()
while IFS= read -r line; do
    [[ -z $line ]] && break  # Break if the line is empty
    filelist+=("$line")
done

# Check if any files were specified
if [ ${#filelist[@]} -eq 0 ]; then
    # No files specified, send all files in the directory
    tar cfzv - * | nc -q 1 ${IPIP} 9
else
    # Send only the specified files
    tar cfzv - "${filelist[@]}" | nc -q 1 ${IPIP} 9
fi

