#!/usr/bin/env bash
#
# install-workshop-tools.sh — set up the SCCM workshop toolkit on your
# OWN Linux box (Ubuntu / Debian / Kali).
#
# Installs, for the user who runs it (no root login, no lab accounts):
#   - OS build prereqs (so impacket's gssapi dep compiles)
#   - uv (Astral) under ~/.local/bin
#   - ~/tools/ checkouts: sccmhunter, PXEHacker, RelayInformer, PetitPotam
#   - ~/venv/pentest: impacket + each tool's requirements + ldeep
#     (ldeep's ldap3 dev-fork installed LAST so it wins)
#   - ~/venv/relayinformer: RelayInformer isolated (its pins fight the rest)
#   - netexec (nxc) via `uv tool install` — isolated, so it can't clobber
#     ldeep's ldap3 fork
#   - a sudo-aware ntlmrelayx.py shim on PATH
#   - venv auto-activation in ~/.bashrc (so ldeep / impacket-* / nxc are
#     on PATH). Deliberately NO per-tool aliases: run the cloned tools as
#     `python3 ~/tools/<tool>/<tool>.py`, exactly as the Misconfiguration
#     Manager docs show.
#
# Idempotent: safe to re-run. Mirrors misc_provision_ubuntu_students.yml
# (keep the two in sync).
#
# Usage:  ./install-workshop-tools.sh        # installs for $USER
#         (needs sudo for the apt step and the /usr/local/bin shim)

set -euo pipefail

log() { printf '\n\033[1;36m[*] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  warn "Run this as your normal user, not root — it installs into \$HOME."
  warn "It will call sudo itself for the apt + shim steps."
  exit 1
fi
command -v apt-get >/dev/null 2>&1 || { warn "This script is apt-based (Ubuntu/Debian/Kali)."; exit 1; }

UV="$HOME/.local/bin/uv"
PENTEST="$HOME/venv/pentest"
RELAY="$HOME/venv/relayinformer"

# ── OS prereqs ───────────────────────────────────────────────────────
log "Installing OS prerequisites (sudo)…"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git curl ca-certificates python3 python3-venv python3-pip python3-dev \
  build-essential libkrb5-dev libssl-dev libffi-dev \
  ruby ruby-dev   # ruby for evil-winrm

# ── uv ───────────────────────────────────────────────────────────────
if [ ! -x "$UV" ]; then
  log "Installing uv (Astral)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  log "uv already present ($("$UV" --version))."
fi
export PATH="$HOME/.local/bin:$PATH"

# ── Tool checkouts ───────────────────────────────────────────────────
log "Cloning tool repos into ~/tools …"
mkdir -p "$HOME/tools"
clone() {  # clone() <name> <url>
  local dest="$HOME/tools/$1"
  if [ -d "$dest/.git" ]; then echo "    $1 already cloned"; else git clone --quiet "$2" "$dest"; echo "    cloned $1"; fi
}
clone sccmhunter     https://github.com/garrettfoster13/sccmhunter.git
clone PXEHacker      https://github.com/chryzsh/PXEHacker.git
clone RelayInformer  https://github.com/zyn3rgy/RelayInformer.git
clone PetitPotam     https://github.com/topotam/PetitPotam.git

# ── Shared pentest venv ──────────────────────────────────────────────
log "Creating ~/venv/pentest …"
[ -x "$PENTEST/bin/python" ] || "$UV" venv "$PENTEST"

log "Installing impacket into pentest venv …"
"$UV" pip install --reinstall --python "$PENTEST/bin/python" impacket

log "Installing each cloned tool's requirements.txt …"
for t in sccmhunter PXEHacker RelayInformer PetitPotam; do
  req="$HOME/tools/$t/requirements.txt"
  [ -f "$req" ] && "$UV" pip install --python "$PENTEST/bin/python" -r "$req" || true
done

# ── RelayInformer: isolated venv (its pins fight impacket/ldeep) ─────
log "Installing RelayInformer into its own venv (~/venv/relayinformer) …"
[ -x "$RELAY/bin/python" ] || "$UV" venv "$RELAY"
"$UV" pip install --python "$RELAY/bin/python" -e "$HOME/tools/RelayInformer/Python/"

# ── ldeep LAST: overrides ldap3 with the dev-branch fork (needs ENCRYPT)
# Order matters — earlier installs pull mainline ldap3 transitively;
# running ldeep's stack last leaves the dev fork + pinned pyasn1 in place.
log "Installing ldeep stack LAST (ldap3 dev fork) …"
"$UV" pip install --reinstall --python "$PENTEST/bin/python" \
  "pyasn1==0.4.8" "git+https://github.com/cannatag/ldap3.git@dev" ldeep

# ── netexec: isolated via uv tool (never touches the pentest venv) ───
log "Installing netexec (nxc) as an isolated uv tool …"
"$UV" tool install --force netexec >/dev/null 2>&1 \
  && echo "    nxc -> $HOME/.local/bin/nxc" \
  || warn "netexec install had issues — retry: uv tool install netexec"

# ── evil-winrm (ruby gem) — a dedicated WinRM shell for the CRED-6 payoff
log "Installing evil-winrm (ruby gem, user scope) …"
gem install --user-install evil-winrm >/dev/null 2>&1 \
  && echo "    evil-winrm -> $(ruby -e 'print Gem.user_dir')/bin/evil-winrm" \
  || warn "evil-winrm install had issues — retry: gem install --user-install evil-winrm"

# ── sudo-aware ntlmrelayx shim ───────────────────────────────────────
# ntlmrelayx binds privileged ports, so it needs root — but root's PATH
# doesn't see the venv. This shim lets `sudo ntlmrelayx.py …` just work.
log "Installing sudo-aware ntlmrelayx.py shim (sudo) …"
sudo tee /usr/local/bin/ntlmrelayx.py >/dev/null <<EOF
#!/usr/bin/env bash
# Auto-generated by install-workshop-tools.sh — runs the invoking user's
# venv ntlmrelayx under sudo with the venv's python.
exec "$PENTEST/bin/ntlmrelayx.py" "\$@"
EOF
sudo chmod 0755 /usr/local/bin/ntlmrelayx.py

# ── Login UX: activate the venv (NO per-tool aliases) ────────────────
log "Wiring venv auto-activation into ~/.bashrc …"
MARK_BEGIN="# >>> workshop-tools venv >>>"
MARK_END="# <<< workshop-tools venv <<<"
if ! grep -qF "$MARK_BEGIN" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

$MARK_BEGIN
# Auto-activate the pentest venv so ldeep / impacket-* / nxc are on PATH.
[ -f "\$HOME/venv/pentest/bin/activate" ] && . "\$HOME/venv/pentest/bin/activate"
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) export PATH="\$HOME/.local/bin:\$PATH";; esac
# ruby gem user bin (evil-winrm)
command -v ruby >/dev/null 2>&1 && export PATH="\$(ruby -e 'print Gem.user_dir')/bin:\$PATH"
# No per-tool aliases on purpose — run cloned tools by path, e.g.
#   python3 ~/tools/sccmhunter/sccmhunter.py find -u USER -p PASS -d DOMAIN -dc-ip DC_IP
$MARK_END
EOF
  echo "    added (re-login or: source ~/.bashrc)"
else
  echo "    already present"
fi

# ── Report ───────────────────────────────────────────────────────────
log "Install report:"
echo "  uv:            $("$UV" --version 2>&1 || echo missing)"
echo "  pentest py:    $("$PENTEST/bin/python" --version 2>&1)"
echo "  impacket:      $("$PENTEST/bin/python" -c 'import impacket; print(impacket.__version__)' 2>&1 || echo missing)"
echo "  ldeep:         $("$PENTEST/bin/ldeep" --version 2>&1 | head -1 || echo missing)"
echo "  nxc:           $("$HOME/.local/bin/nxc" --version 2>&1 | head -1 || echo 'missing (uv tool install netexec)')"
echo "  evil-winrm:    $(command -v evil-winrm >/dev/null 2>&1 && evil-winrm --version 2>&1 | head -1 || echo 'run: gem install --user-install evil-winrm')"
echo "  sccmhunter:    $([ -f "$HOME/tools/sccmhunter/sccmhunter.py" ] && echo present || echo missing)"
echo "  PXEHacker:     $([ -f "$HOME/tools/PXEHacker/pxehacker.py" ] && echo present || echo missing)"
echo "  RelayInformer: $("$RELAY/bin/relayinformer" --help >/dev/null 2>&1 && echo 'installed (cmd: ~/venv/relayinformer/bin/relayinformer)' || echo missing)"
echo "  PetitPotam:    $([ -f "$HOME/tools/PetitPotam/PetitPotam.py" ] && echo present || echo missing)"

cat <<'EOF'

Done. Open a new shell (or `source ~/.bashrc`) to pick up the venv.

How to run things:
  python3 ~/tools/sccmhunter/sccmhunter.py find -u USER -p PASS -d DOMAIN -dc-ip DC_IP
  python3 ~/tools/PetitPotam/PetitPotam.py <listener> <target> -u USER -p PASS -d DOMAIN
  ldeep ldap -u USER -p PASS -d DOMAIN -s ldap://DC_IP <query>
  nxc smb TARGET -u USER -p PASS            # (Pwn3d!) = local admin
  evil-winrm -i TARGET -u USER -p PASS      # interactive shell over WinRM

sudo is needed for ONLY two things (venv-under-sudo is handled for you):
  sudo ntlmrelayx.py -t TARGET -smb2support           # shim on PATH
  sudo ~/venv/pentest/bin/python ~/tools/PXEHacker/pxehacker.py discover   # raw sockets
Everything else runs without sudo.
EOF
