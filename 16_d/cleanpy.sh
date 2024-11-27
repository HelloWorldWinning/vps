#!/bin/bash

# Check if input file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 input.py [output.py]"
    echo "If output.py is not specified, will create input_cleaned.py"
    exit 1
fi

input_file="$1"

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist"
    exit 1
fi

# Set output filename
if [ $# -eq 2 ]; then
    output_file="$2"
else
    filename="${input_file%.*}"
    output_file="${filename}_cleaned.py"
fi

# Process the Python file:
# 1. Remove comments and docstrings
# 2. Remove empty lines and lines with only whitespace
# 3. Preserve empty lines that are syntactically important (e.g., between function definitions)
python3 -c "
import io
import tokenize

def remove_comments_and_docstrings(source):
    io_obj = io.StringIO(source)
    out = ''
    prev_toktype = tokenize.INDENT
    last_col = 0
    last_lineno = -1

    tokgen = tokenize.generate_tokens(io_obj.readline)
    for tok in tokgen:
        token_type = tok.type
        token_string = tok.string
        start_line, start_col = tok.start
        end_line, end_col = tok.end

        if start_line > last_lineno:
            last_col = 0
        if start_col > last_col:
            out += (' ' * (start_col - last_col))

        if token_type == tokenize.COMMENT:
            continue
        elif token_type == tokenize.STRING:
            if prev_toktype != tokenize.INDENT and prev_toktype != tokenize.NEWLINE and prev_toktype != tokenize.DEDENT:
                # Not a docstring
                out += token_string
            else:
                # Docstring; skip it
                continue
        else:
            out += token_string

        prev_toktype = token_type
        last_col = end_col
        last_lineno = end_line

    return out

def process_code(content):
    code_without_comments = remove_comments_and_docstrings(content)
    # Now process line by line
    lines = code_without_comments.split('\\n')
    cleaned_lines = []
    prev_line_empty = False
    for line in lines:
        # Strip whitespace
        processed_line = line.rstrip()
        # Add non-empty lines
        if processed_line:
            cleaned_lines.append(processed_line)
            prev_line_empty = False
        elif not prev_line_empty and any(cleaned_lines) and \
             (cleaned_lines[-1].startswith(('def ', 'class ')) or \
              cleaned_lines[-1].endswith(':')):
            # Preserve empty line
            cleaned_lines.append('')
            prev_line_empty = True
        # Else skip the empty line
    return '\\n'.join(cleaned_lines)

# Read input file
with open('$input_file', 'r') as f:
    content = f.read()

# Process content
minimized = process_code(content)

# Write output
with open('$output_file', 'w') as f:
    f.write(minimized)
"

# Check if the process was successful
if [ $? -eq 0 ]; then
    echo "Successfully created minimized file: $output_file"
    # Show size reduction
    original_size=$(wc -c < "$input_file")
    new_size=$(wc -c < "$output_file")
    reduction=$(( (original_size - new_size) * 100 / original_size ))
    echo "Size reduction: $reduction% (from $original_size to $new_size bytes)"
else
    echo "Error occurred while processing the file"
    exit 1
fi

