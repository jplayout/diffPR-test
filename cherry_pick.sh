#!/bin/bash

set -eEu -o pipefail

: "${SOURCE_REPO?"ERROR: SOURCE_REPO undefined"}"
: "${TARGET_REPO?"ERROR: USER_NAME undefined"}"

clone_repo() {
    local repo_url=$1
    local repo_dir=$2
    if [ ! -d "$repo_dir" ]; then
        git clone "$repo_url" "$repo_dir"
    else
        echo "Repository already cloned."
    fi
}

get_commits() {
    local source_repo=$1
    git -C "$source_repo" log --oneline
}

create_pr() {
    local target_repo=$1
    local branch_name=$2
    local pr_title=$3
    local pr_body=$4
    gh pr create --repo "$target_repo" --head "$branch_name" --title "$pr_title" --body "$pr_body" --reviewer "jplayout"
}
git config --global merge.conflictstyle diff3

# Clone repositories
clone_repo "https://github.com/$SOURCE_REPO.git" "$SOURCE_REPO"
clone_repo "https://github.com/$TARGET_REPO.git" "$TARGET_REPO"

# Add the target repository as a remote in the source repository if it doesn't already exist
if ! git -C "$SOURCE_REPO" remote | grep -q "target-repo"; then
    git -C "$SOURCE_REPO" remote add target-repo "https://github.com/$TARGET_REPO.git"
fi
git -C "$SOURCE_REPO" fetch target-repo

# Get missing commits
echo "Fetching commits that are in the source repo but not in the target repo..."
commits=$(get_commits "$SOURCE_REPO")
if [ -z "$commits" ]; then
    echo "No missing commits found."
    exit 0
fi
printf "Missing commits: \n%s" "$commits" 

# Select commits to include in the PR
read -rp "Enter the commit hashes to include in the PR (space-separated): " selected_commits

# Create a new branch in the target repo
branch_name="pr-$(date +%Y%m%d%H%M%S)"
git -C "$TARGET_REPO" checkout -b "$branch_name"

# Fetch latest from the source repo (and its branches) into the target repo
git -C "$TARGET_REPO" fetch "https://github.com/$SOURCE_REPO.git"

# Cherry-pick selected commits
for commit in $selected_commits; do
    echo "Attempting to cherry-pick commit $commit..."
    git -C "$TARGET_REPO" cherry-pick "$commit" || {
        echo "Cherry-pick failed due to conflicts, skipping to next commit..."
        git -C "$TARGET_REPO" add -A  # Stage the conflicting files (this will indicate a merge conflict)
        git -C "$TARGET_REPO" commit --amend --no-edit  # Amend the commit to mark it as conflicted
    }
done

# Push the new branch to the target repo
git -C "$TARGET_REPO" push origin "$branch_name"

#PR creation
pr_title="[CHERRY PICK] Commits from $SOURCE_REPO to $TARGET_REPO"
pr_body="PR generated to cherry pick those commits"
for commit in $selected_commits; do
    pr_body+="\n$commit"
done
pr_body+="\nFrom $SOURCE_REPO to $TARGET_REPO"
create_pr "$TARGET_REPO" "$branch_name" "$pr_title" "$pr_body"
echo "Pull request created successfully!"