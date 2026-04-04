#!/usr/bin/env bash
set -euo pipefail

REPO="${DEMIOURGOS_RELEASE_REPO:-sarveshdakhore/demiourgos-client-dist}"
VERSION="${DEMIOURGOS_VERSION:-latest}"
INSTALL_DIR="${DEMIOURGOS_INSTALL_DIR:-}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() {
  printf "[demiourgos-install] %s\n" "$*"
}

fail() {
  printf "[demiourgos-install] error: %s\n" "$*" >&2
  exit 1
}

detect_platform() {
  local os arch platform
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *) fail "unsupported OS: $os (supported: Linux, Darwin)" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) fail "unsupported architecture: $arch (supported: x86_64/amd64, arm64/aarch64)" ;;
  esac

  platform="${os}-${arch}"
  case "$platform" in
    linux-amd64|darwin-arm64) ;;
    darwin-amd64) fail "intel macOS builds are not published yet" ;;
    *) fail "unsupported platform: ${platform} (supported: linux-amd64, darwin-arm64)" ;;
  esac

  printf "%s" "$platform"
}

resolve_version() {
  if [[ "$VERSION" != "latest" ]]; then
    printf "%s" "${VERSION#v}"
    return
  fi

  local api tag
  api="https://api.github.com/repos/${REPO}/releases/latest"
  tag="$(curl -fsSL "$api" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$tag" ]] || fail "could not resolve latest release tag from ${api}"
  printf "%s" "${tag#v}"
}

verify_sha256() {
  local file checksum_file
  file="$1"
  checksum_file="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$checksum_file")")
  else
    local expected actual
    expected="$(awk '{print $1}' "$checksum_file")"
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || fail "sha256 mismatch for $(basename "$file")"
  fi
}

write_channel_marker() {
  local marker_dir marker_file
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    marker_dir="${XDG_CONFIG_HOME}/demiourgos"
  else
    marker_dir="${HOME}/.config/demiourgos"
  fi
  marker_file="${marker_dir}/install_channel.json"
  mkdir -p "$marker_dir"
  cat > "$marker_file" <<JSON
{"channel":"curl"}
JSON
}

main() {
  local platform version asset url sha_url install_target
  local member_list
  platform="$(detect_platform)"
  version="$(resolve_version)"

  asset="demiourgos-${version}-${platform}.tar.gz"
  url="https://github.com/${REPO}/releases/download/v${version}/${asset}"
  sha_url="${url}.sha256"

  log "installing demiourgos v${version} for ${platform}"
  curl -fsSL "$url" -o "${TMP_DIR}/${asset}"
  curl -fsSL "$sha_url" -o "${TMP_DIR}/${asset}.sha256"

  verify_sha256 "${TMP_DIR}/${asset}" "${TMP_DIR}/${asset}.sha256"
  member_list="$(tar -tzf "${TMP_DIR}/${asset}")"
  if printf "%s\n" "$member_list" | grep -E '\.map$' >/dev/null; then
    fail "archive contains .map files"
  fi
  if printf "%s\n" "$member_list" | grep -E '^/|(^|/)\.\.(/|$)' >/dev/null; then
    fail "archive contains unsafe paths"
  fi
  tar -xzf "${TMP_DIR}/${asset}" -C "${TMP_DIR}"

  if [[ -f "${TMP_DIR}/demiourgos" ]]; then
    :
  else
    local found
    found="$(find "${TMP_DIR}" -type f -name demiourgos | head -n1 || true)"
    [[ -n "$found" ]] || fail "archive did not contain demiourgos binary"
    cp "$found" "${TMP_DIR}/demiourgos"
  fi

  if [[ -z "$INSTALL_DIR" ]]; then
    if [[ -w "/usr/local/bin" ]]; then
      INSTALL_DIR="/usr/local/bin"
    else
      INSTALL_DIR="${HOME}/.local/bin"
    fi
  fi
  mkdir -p "$INSTALL_DIR"

  install_target="${INSTALL_DIR}/demiourgos"
  cp "${TMP_DIR}/demiourgos" "$install_target"
  chmod +x "$install_target"
  write_channel_marker

  log "installed to ${install_target}"
  if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    log "warning: ${INSTALL_DIR} is not in PATH"
  fi
  log "run: demiourgos self update-status --check-now"
}

main "$@"
