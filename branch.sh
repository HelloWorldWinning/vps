#!/bin/bash

# Prompt for a new branch name
echo "Enter a new branch name:"
read new_branch

# Check if the branch name was provided
if [ -z "$new_branch" ]; then
    echo "No branch name provided. Exiting."
    exit 1
fi

# Switch to the new branch locally (creates it if it doesn't exist)
git checkout -b "$new_branch"

# Link the new local branch to the corresponding remote branch
git branch --set-upstream-to=origin/"$new_branch" "$new_branch"

# Add all changes to the staging area
git add .

# Prompt for a commit message
#echo "Enter a commit message:"
#read commit_message
commit_message="init $new_branch"

# Commit the changes
git commit -m "$commit_message"

# Push the new branch to the remote repository
git push -u origin "$new_branch"

