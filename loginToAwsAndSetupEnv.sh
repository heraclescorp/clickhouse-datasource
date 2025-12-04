#!/bin/bash
set +x

# Important note: If executed directly this script will reset the shell to ensure the environment variables are loaded.
# if run in another script it should be sourced instead of run directly. 

# check if we can get the AWS account to see if we're logged in or not
if aws sts get-caller-identity --query "Account" &> /dev/null; then 
  echo "AWS session still valid" ;
else 
  echo "Seems like AWS session is expired attempting to login"
  aws sso login
fi

BASE_DIR=$(dirname -- "${BASH_SOURCE[0]}")
echo "Setting up environment variables"

CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain "aven" --domain-owner "199658938451" --query authorizationToken --output text)
PIP_INDEX_URL="https://aws:${CODEARTIFACT_AUTH_TOKEN}@aven-199658938451.d.codeartifact.us-east-2.amazonaws.com/pypi/aven-packages/simple/"

if [ ! -z "$CI" ]; then
  echo "In CI environment, not resetting shell"
  # I don't love this but the original solution we used to detect wether the yarn config was set in CI was
  # unable to access the file it needed to verify that the setup was correct, this just stops the config
  # from being set when we're "sourcing" the file (ie what the scripts do internally) meaning that this
  # must be run at least once directly before starting, (this is currently what happens)
  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Setting up yarn config for codeartifact"
    # enable corepack in ci
    corepack enable
    yarn config set -H npmRegistryServer "https://aven-199658938451.d.codeartifact.us-east-2.amazonaws.com/npm/aven-packages/"
    yarn config set -H npmPublishRegistry "https://aven-199658938451.d.codeartifact.us-east-2.amazonaws.com/npm/aven-packages/"
    yarn config set -H 'npmRegistries["https://aven-199658938451.d.codeartifact.us-east-2.amazonaws.com/npm/aven-packages/"].npmAlwaysAuth' "true"
    yarn config set -H 'npmRegistries["https://aven-199658938451.d.codeartifact.us-east-2.amazonaws.com/npm/aven-packages/"].npmAuthToken' "${CODEARTIFACT_AUTH_TOKEN}"
  else
    echo "Yarn config for codeartifact already set"
  fi

  yarn config set nodeLinker node-modules

  echo "GIT_HASH=$(git rev-parse --short HEAD)" >> "$GITHUB_ENV"
  echo "GIT_FULL_HASH=$(git rev-parse HEAD)" >> "$GITHUB_ENV"
  echo "GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)" >> "$GITHUB_ENV"
  echo "CODEARTIFACT_AUTH_TOKEN=${CODEARTIFACT_AUTH_TOKEN}" >> "$GITHUB_ENV"
  echo "PIP_INDEX_URL=${PIP_INDEX_URL}" >> "$GITHUB_ENV"
  echo "UV_DEFAULT_INDEX=${PIP_INDEX_URL}" >> "$GITHUB_ENV"

  export PIP_INDEX_URL
  export UV_DEFAULT_INDEX="${PIP_INDEX_URL}"
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "Script is being sourced, not executed directly."
    return 0
  else
    echo "Script is being executed directly exiting."
    exit 0
  fi
fi

uv tool install keyring --with keyrings.codeartifact
# temp, should be done in setupVersionManager.sh
grep -qxF 'export UV_KEYRING_PROVIDER=subprocess' "$HOME/.zshrc" || echo 'export UV_KEYRING_PROVIDER=subprocess' >> "$HOME/.zshrc"
grep -qxF 'export UV_INDEX_CODEARTIFACTS_USERNAME=aws' "$HOME/.zshrc" || echo 'export UV_INDEX_CODEARTIFACTS_USERNAME=aws' >> "$HOME/.zshrc"
grep -qxF 'export PATH="$PATH:$HOME/.local/bin"' "$HOME/.zshrc" || echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$HOME/.zshrc"

export UV_KEYRING_PROVIDER=subprocess
export UV_INDEX_CODEARTIFACTS_USERNAME=aws
export UV_INDEX_CODEARTIFACTS_PASSWORD="$CODEARTIFACT_AUTH_TOKEN"
unset UV_DEFAULT_INDEX # used to be used, no longer needed with newer setups
# This is necessary to avoid multiprocessing errors on OSX
# https://stackoverflow.com/questions/50168647/multiprocessing-causes-python-to-crash-and-gives-an-error-may-have-been-in-progr
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

export no_proxy=*

export GIT_HASH=$(git rev-parse --short HEAD)

export GIT_FULL_HASH=$(git rev-parse HEAD)

export GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

export UV_INDEX_URL=$PIP_INDEX_URL

export PIP_INDEX_URL

# reset the shell to ensure the environment variables are loaded
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "Script is being sourced, not executed directly."
else
  $BASE_DIR/setup/setupDocker.sh
  echo "Script is being executed directly. Resetting shell to apply environment variables."
  if [ -n "$ZSH_VERSION" ]; then
    # Already running in zsh, source zshrc
    source $HOME/.zshrc
  else
    # Not in zsh, exec zsh
    exec zsh
  fi
fi