#!/bin/bash

set -eEu -o pipefail

: "${SOURCE_REPO?"ERROR: SOURCE_REPO undefined"}"
: "${SOURCE_BRANCH?"ERROR: SOURCE_BRANCH undefined"}"
: "${TARGET_REPO?"ERROR: USER_NAME undefined"}"

clone_repo() {
    if [ ! -d "${2}" ]; then
        git clone "${1}" "${2}"
    else
        echo "Repository already cloned."
    fi
}

git config --global merge.conflictstyle diff3

# Clone repositories
clone_repo "https://github.com/${SOURCE_REPO}.git" "${SOURCE_REPO}"
clone_repo "https://github.com/${TARGET_REPO}.git" "${TARGET_REPO}"

# Add the target repository as a remote in the source repository if it doesn't already exist
if ! git -C "${SOURCE_REPO}" remote | grep -q "target-repo"; then
    git -C "${SOURCE_REPO}" remote add target-repo "https://github.com/${TARGET_REPO}.git"
fi
git -C "${SOURCE_REPO}" fetch target-repo

# If a list of commits is provided as a parameter, use it. Otherwise, ask for input.
if [ $# -gt 0 ]; then
    selected_commits="$@"
else
    # Get missing commits
    echo "Fetching commits that are in the source repo but not in the target repo..."
    commits=$(git -C "${SOURCE_REPO}" log --oneline "${SOURCE_BRANCH}")
    if [ -z "${commits}" ]; then
        echo "No missing commits found."
        exit 0
    fi
    printf "Missing commits from %s branch: \n%s" "${SOURCE_BRANCH}" "${commits}"
    printf "\n"
    # Select commits to include in the PR
    read -rp "Enter the commit hashes to include in the PR (space-separated): " selected_commits
fi

# Create a new branch in the target repo
branch_name="pr-$(date +%Y%m%d%H%M%S)"
git -C "${TARGET_REPO}" checkout -b "${branch_name}"

# Fetch latest from the source repo (and its branches) into the target repo
git -C "${TARGET_REPO}" fetch "https://github.com/${SOURCE_REPO}.git"

# Cherry-pick selected commits
for commit in ${selected_commits}; do
    echo "Attempting to cherry-pick commit ${commit}..."
    
    # Try to cherry-pick the commit
    if ! git -C "${TARGET_REPO}" cherry-pick "${commit}"; then
        echo "Cherry-pick failed due to conflicts, leaving conflict for reviewer..."
        # Stage the conflicting files, but don't commit
        git -C "${TARGET_REPO}" add -A  # Stage the conflicting files

        # Annotate the conflict in the file with the commit hash
        for file in $(git -C "${TARGET_REPO}" diff --name-only --diff-filter=U); do
            echo "Conflict detected in file ${file} due to commit ${commit}" >> "${file}"
        done
        
        # Commit the conflict for review
        git -C "${TARGET_REPO}" commit -m "Cherry-pick commit ${commit} with conflict markers"
    fi
done

# Push the branch to the remote repository
git -C "${TARGET_REPO}" push origin "${branch_name}"

# Create the PR using GitHub CLI
pr_title="[CHERRY PICK] Commits from ${SOURCE_REPO} to ${TARGET_REPO}"
pr_body="PR generated to cherry-pick these commits. Conflicts may exist and need to be resolved manually.
From ${SOURCE_REPO} to ${TARGET_REPO}"

# Create the PR
echo "Creating PR..."
gh pr create --repo "${TARGET_REPO}" --head "${branch_name}" --title "${pr_title}" --body "${pr_body}" --reviewer "jplayout"

echo "Pull request created successfully!"