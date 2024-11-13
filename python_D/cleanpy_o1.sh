#!/bin/bash

if [ "$#" -eq 1 ]; then
    infile="$1"
    outfile="${infile%.*}_cleaned.py"
elif [ "$#" -eq 2 ]; then
    infile="$1"
    outfile="$2"
else
    echo "Usage: $0 input.py [output.py]"
    exit 1
fi

python3 - <<END
import sys
import tokenize
import io
import re

def remove_comments_and_docstrings(source):
    """
    Returns 'source' minus comments and docstrings.
    """
    io_obj = io.StringIO(source)
    out = ''
    prev_toktype = tokenize.INDENT
    last_lineno = -1
    last_col = 0

    tokens = tokenize.generate_tokens(io_obj.readline)
    for tok in tokens:
        token_type = tok.type
        token_string = tok.string
        start_line, start_col = tok.start
        end_line, end_col = tok.end

        if start_line > last_lineno:
            last_col = 0
        if start_col > last_col:
            out += ' ' * (start_col - last_col)

        if token_type == tokenize.COMMENT:
            continue
        elif token_type == tokenize.STRING:
            if prev_toktype != tokenize.INDENT and prev_toktype != tokenize.NEWLINE and prev_toktype != tokenize.DEDENT:
                # This is a regular string, not a docstring
                out += token_string
            else:
                # It's a docstring, skip it
                continue
        else:
            out += token_string

        prev_toktype = token_type
        last_col = end_col
        last_lineno = end_line

    return out

infile = '${infile}'
outfile = '${outfile}'

with open(infile, 'r') as f:
    source = f.read()

cleaned_source = remove_comments_and_docstrings(source)

# Remove extra empty lines
cleaned_source = re.sub(r'\n\s*\n', '\n', cleaned_source)

with open(outfile, 'w') as f:
    f.write(cleaned_source.strip() + '\n')
END

