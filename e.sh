#!/bin/bash
e() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: fd_func <search_term> [additional_terms...]"
        return 1
    fi
    local search_term="$1"
    shift
    local additional_terms=("$@")
    /usr/local/bin/fd --absolute-path --color=never "$search_term" "${additional_terms[@]}" | \
        rg --color=always \
           --colors 'match:fg:yellow' \
           --colors 'line:none' \
           --regexp "[^/]*${search_term}[^/]*"
}
