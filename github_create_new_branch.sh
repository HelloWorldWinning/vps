#!/bin/bash

# Step 1: Input GitHub username
read -p "Enter your GitHub username (default: HelloWorldWinning): " github_name
github_name=${github_name:-HelloWorldWinning}

# Step 2: Input main branch name
read -p "Enter the main branch name (default: main): " main_branch
main_branch=${main_branch:-main}

# Step 3: Input access token and branch name
read -p "Enter your GitHub access token: " access_token
read -p "Enter the branch name: " branch_name

# Create a new directory for the project
mkdir "$branch_name"
cd "$branch_name"

# Initialize a new Git repository
git init

# Set the default branch name
git config --global init.defaultBranch "$main_branch"

# Rename the current branch to the specified main branch
git branch -m "$main_branch"

# Create a README file
echo "# $branch_name" > README.md

# Stage the README file
git add README.md

# Commit the changes
git commit -m "Initial commit"

# Create the repository on GitHub using the GitHub API
repo_data='{"name":"'$branch_name'","private":false}'
repo_url=$(curl -s -H "Authorization: token $access_token" -d "$repo_data" https://api.github.com/user/repos | grep -o '"clone_url": "[^"]*' | grep -o '[^"]*$')

# Set the remote repository URL
remote_url="https://${access_token}@${repo_url#https://}"

# Add the remote repository
git remote add origin "$remote_url"

# Push the changes to the remote repository
git push -u origin "$main_branch"

echo "Repository created successfully!"
echo "Remote URL: $remote_url"
