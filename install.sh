#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${BOOTSTRAP_GITHUB_OWNER:-2048TB}"
REPO_NAME="${BOOTSTRAP_GITHUB_REPO:-dev-setup}"
REPO_REF="${BOOTSTRAP_GITHUB_REF:-main}"
ARCHIVE_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${REPO_REF}"
BOOTSTRAP_TMPDIR=""

have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

die() {
	echo "error: $*" >&2
	exit 1
}

download_file() {
	local url="$1"
	local output="$2"
	local description="$3"

	if ! curl -fsSL "$url" -o "$output"; then
		echo "error: failed to download ${description}: ${url}" >&2
		return 1
	fi
}

is_macos() {
	[ "$(uname -s)" = "Darwin" ]
}

get_bash_major_version() {
	local bash_bin="$1"

	# shellcheck disable=SC2016
	"$bash_bin" -lc 'printf "%s" "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || printf '0'
}

select_runner_bash() {
	local candidate version

	for candidate in "${BASH:-}" /opt/homebrew/bin/bash /usr/local/bin/bash /bin/bash "$(command -v bash 2>/dev/null || true)"; do
		[ -n "$candidate" ] || continue
		[ -x "$candidate" ] || continue

		version="$(get_bash_major_version "$candidate")"
		if [ "${version:-0}" -ge 4 ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

find_brew_bin() {
	local candidate

	for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null || true)"; do
		[ -n "$candidate" ] || continue
		[ -x "$candidate" ] || continue
		printf '%s\n' "$candidate"
		return 0
	done

	return 1
}

bootstrap_runner_bash_on_macos() {
	local brew_bin=""
	local brew_install_script=""

	if ! is_macos; then
		return 1
	fi

	if ! brew_bin="$(find_brew_bin)"; then
		echo "==> Homebrew not found; installing Homebrew to bootstrap Bash 4+"
		brew_install_script="$(mktemp)" || return 1
		if ! download_file "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$brew_install_script" "Homebrew install script"; then
			rm -f "$brew_install_script"
			return 1
		fi
		if ! NONINTERACTIVE=1 /bin/bash "$brew_install_script"; then
			rm -f "$brew_install_script"
			return 1
		fi
		rm -f "$brew_install_script"
		brew_bin="$(find_brew_bin)" || return 1
	fi

	eval "$("$brew_bin" shellenv)"

	if ! select_runner_bash >/dev/null 2>&1; then
		echo "==> Installing modern Bash via Homebrew"
		"$brew_bin" install bash || return 1
	fi

	return 0
}

main() {
	local runner_bash archive_path extracted_dir

	if ! have_cmd curl; then
		die "curl is required"
	fi

	if ! have_cmd tar; then
		die "tar is required"
	fi

	if ! runner_bash="$(select_runner_bash)"; then
		if is_macos && bootstrap_runner_bash_on_macos; then
			runner_bash="$(select_runner_bash)" || true
		fi
	fi

	if [ -z "${runner_bash:-}" ]; then
		cat >&2 <<'EOF'
error: setup.sh requires Bash 4.0 or newer.
install.sh already tried to bootstrap Homebrew and Bash automatically on macOS.
If that failed, install modern Bash first:
  brew install bash
Then rerun the install command.
EOF
		exit 1
	fi

	BOOTSTRAP_TMPDIR="$(mktemp -d)" || die "failed to create temporary directory"
	trap 'rm -rf "${BOOTSTRAP_TMPDIR:-}"' EXIT

	archive_path="$BOOTSTRAP_TMPDIR/repo.tar.gz"
	extracted_dir="$BOOTSTRAP_TMPDIR/${REPO_NAME}-${REPO_REF}"

	echo "==> Downloading ${REPO_OWNER}/${REPO_NAME}@${REPO_REF}"
	download_file "$ARCHIVE_URL" "$archive_path" "repository archive" || exit 1

	echo "==> Extracting archive"
	if ! tar -xzf "$archive_path" -C "$BOOTSTRAP_TMPDIR"; then
		die "failed to extract repository archive"
	fi

	if [ ! -f "$extracted_dir/setup.sh" ]; then
		die "setup.sh was not found in downloaded archive"
	fi

	echo "==> Running setup.sh"
	if [ -t 1 ] && [ -r /dev/tty ] && [ ! -t 0 ]; then
		exec "$runner_bash" "$extracted_dir/setup.sh" "$@" </dev/tty
	fi
	exec "$runner_bash" "$extracted_dir/setup.sh" "$@"
}

main "$@"
