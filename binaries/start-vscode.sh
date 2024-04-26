#!/bin/bash
set -o pipefail -o nounset
: "${VSCODE_KEYRING_PASS:?Variable not set or empty}"

# Make sure permissions for all mounted directories are correct
USERNAME=$(whoami)
sudo chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
sudo chown -R ${USERNAME}:${USERNAME} /etc/home

# Copy all files from /etc/home to the user's home directory if the /etc/home directory exists
if [[ -d /etc/home ]]; then
	cp -rf /etc/home/* ~
	cp -rf /etc/home/.[^.]* ~
fi

# Start SSH
sudo service ssh start

# Set git config to use environment variables.
# All of these variables can be set/overridden using the following naming convention:
# GIT_{CONFIG_NAME}_{CONFIG_KEY} where:
# - {CONFIG_NAME} is the name of the config file (e.g. GLOBAL, SYSTEM, LOCAL)
# - {CONFIG_KEY} is the key of the config value (e.g. USER_NAME, USER_EMAIL)
# For example, to set the global user.name config, you would set the GIT_GLOBAL_USER_NAME environment variable.

# Get all the environment variables that start with GIT_
env | grep -o '^GIT_[^=]\+' | while read -r git_config; do
	# Get the value of the environment variable
	git_config_value="${!git_config}"
	# Get the config name and key
	git_config_name=$(echo "${git_config}" | cut -d_ -f2 | tr '[:upper:]' '[:lower:]')
	git_config_key=$(echo "${git_config}" | cut -d_ -f3- | tr '[:upper:]' '[:lower:]' | tr '_' '.')
	# Set the git config
	git config --"${git_config_name}" "${git_config_key}" "${git_config_value}"
done

# If the GITHUB_TOKEN or GH_TOKEN environment variables are set, run `gh auth setup-git` in order to allow for gh to authenticate git
if [[ -n ${GITHUB_TOKEN-} || -n ${GH_TOKEN-} ]]; then
	gh auth setup-git
fi

# Import the GPG key from the GPG_SECRET_KEY environment variable. If the GPG_PASSPHRASE environment variable is set, use it to unlock the GPG key.
if [[ -n ${GPG_SECRET_KEY-} ]]; then
	echo "${GPG_SECRET_KEY}" | base64 -d | gpg --batch --import
	if [[ -n ${GPG_PASSPHRASE-} ]]; then
		echo "${GPG_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --pinentry-mode loopback --output /dev/null --sign
	fi

	# Set the GPG_TTY environment variable to prevent pinentry from hanging
	export GPG_TTY=$(tty)

	# Set the default GPG key to the key imported
	default_key=$(gpg --list-secret-keys --keyid-format LONG)

	# Get the key ID of the default key
	default_key_id=$(echo "${default_key}" | grep -E "^sec" | awk '{print $2}' | awk -F'/' '{print $2}')

	# Check if the key is available in gh cli. If it's not added, add it.
	if [[ -n ${GITHUB_TOKEN-} || -n ${GH_TOKEN-} ]]; then
		gh_key=$(gh api /user/gpg_keys --paginate --jq ".[] | select(.key_id == \"${default_key_id}\")")
		if [[ -z ${gh_key} ]]; then
			# Get the key file
			key_file=$(mktemp)
			gpg --armor --export "${default_key_id}" >"${key_file}"

			# Add the key to GitHub
			gh gpg-key add "${key_file}" --title "GPG key for ${hostname}"
		fi
	fi

	# Set git config to verify commits with the default GPG key
	git config --global user.signingkey "${default_key_id}"
	git config --global commit.gpgsign true
fi

# Run a dbus session, which unlocks the gnome-keyring and runs the VS Code Server inside of it
dbus-run-session -- sh -c "(echo ${VSCODE_KEYRING_PASS} | gnome-keyring-daemon --unlock) \
    && /usr/local/bin/initialise-vscode.sh \
    && code serve-web \
        --disable-telemetry \
        --without-connection-token \
        --accept-server-license-terms \
        --host 0.0.0.0"
