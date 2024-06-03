#!/bin/bash
# Step 1: Input GitHub username
read -p "Enter your GitHub username (default: HelloWorldWinning): " github_name
github_name=${github_name:-HelloWorldWinning}
# Step 2: Input main branch name
read -p "Enter the main branch name (default: main): " main_branch
main_branch=${main_branch:-main}
# Step 3: Input access token and project name
read -p "Enter your GitHub access token: " access_token
read -p "Enter the project name: " project_name
# Step 4: Input repository visibility (default: private)
read -p "Enter the repository visibility (public/private) (default: private): " repo_visibility
repo_visibility=${repo_visibility:-private}
# Set the repository visibility flag
if [ "$repo_visibility" == "public" ]; then
  private_flag=false
else
  private_flag=true
fi
# Create a new directory for the project
mkdir "$project_name"
cd "$project_name"
# Initialize a new Git repository
git init
# Set the default branch name
git config --global init.defaultBranch "$main_branch"
# Rename the current branch to the specified main branch
git branch -m "$main_branch"
# Create a README file
echo "# $project_name" > README.md
# Stage the README file
git add README.md
# Commit the changes
git commit -m "Initial commit"
# Create the repository on GitHub using the GitHub API
repo_data='{"name":"'$project_name'","private":'$private_flag'}'
repo_url=$(curl -s -H "Authorization: token $access_token" -d "$repo_data" https://api.github.com/user/repos | grep -o '"clone_url": "[^"]*' | grep -o '[^"]*$')
# Set the remote repository URL
remote_url="https://${access_token}@${repo_url#https://}"
# Add the remote repository
git remote add origin "$remote_url"
# Push the changes to the remote repository
git push -u origin "$main_branch"
echo "Repository created successfully!"
echo "Remote URL: $remote_url"
