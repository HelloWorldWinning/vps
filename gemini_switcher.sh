#!/usr/bin/env bash
# =============================================================================
# gemini_switcher.sh
#   Interactive manager for multiple agy (Antigravity CLI) login profiles on
#   one Linux machine.
#
# USAGE
#   bash gemini_switcher.sh          (no arguments; everything is in the menu)
#
# WHAT A PROFILE IS
#   A profile is a command in BIN_DIR (default /usr/local/bin), e.g. "agy_xyz".
#   Running "agy_xyz <args>" is the same as running "agy <args>", except that
#   agy uses this private data directory instead of ~/.gemini :
#       ~/.config/gemini_switcher/profiles/agy_xyz/gemini
#   A new profile starts empty, like agy on a brand new VPS: its own login,
#   settings, MCP config, skills, prompt history and onboarding.
#
# WHAT IS SHARED
#   Only conversation data. Inside every profile these entries are symlinks
#   into SHARED_ROOT (default ~/.gemini, the directory plain "agy" uses):
#       antigravity-cli/conversations            conversation files
#       antigravity-cli/presence                 one lock file per conversation
#       antigravity-cli/brain                    per-conversation artifacts
#       antigravity-cli/annotations              per-conversation annotations
#       antigravity-cli/conversation_summaries.db        conversation index
#       antigravity-cli/cache/last_conversations.json    folder -> last
#                                                        conversation ("-c")
#       antigravity-cli/cache/conversation_metadata.json
#   So "agy -c", "agy_xyz -c" and "xxoo -c" continue the same conversation,
#   and "--conversation <id>" works from every profile.
#
# MENU ACTIONS
#   list     show every profile, its Google account and its wrapper state
#   add      create a new, empty profile and its command
#   del      delete a profile (private data + command; conversations stay)
#   rename   rename a profile and its command
#   update   rewrite every wrapper script from the template in this file and
#            repair the shared links. It never updates the agy binary.
#   doctor   check the setup. It changes nothing.
#
# FILES
#   ~/.config/gemini_switcher/config               settings (created on first run)
#   ~/.config/gemini_switcher/profiles/<name>/     one directory per profile
#   BIN_DIR/<name>                                 the wrapper script
#
# NOTES
#   - Linux only. On macOS agy keeps its login in the keychain, so
#     --gemini_dir does not separate accounts there.
#   - Wrappers are self-contained bash files. They keep working if this
#     script is moved or deleted.
#   - After editing the config file, run "update" so the wrappers pick it up.
# =============================================================================

set -u

GSW_TEMPLATE_VERSION=1
GSW_MARKER='gemini_switcher:managed-wrapper'
GSW_HOME=${GEMINI_SWITCHER_HOME:-$HOME/.config/gemini_switcher}
GSW_CONFIG=$GSW_HOME/config
GSW_PROFILES=$GSW_HOME/profiles
GSW_RESERVED_NAMES=(agy default gemini gemini_switcher)

# Values the wrappers also use. Filled by gsw_load_config.
GSW_PROFILE=
GSW_GEMINI_DIR=
GSW_SHARED_ROOT=
GSW_SHARED_DIRS=()
GSW_SHARED_FILES=()

GSW_ANSWER=
GSW_PICK=

# -----------------------------------------------------------------------------
# Functions copied into every wrapper (see gsw_render_wrapper).
# They only use: GSW_PROFILE GSW_GEMINI_DIR GSW_SHARED_ROOT GSW_SHARED_DIRS
# GSW_SHARED_FILES.
# -----------------------------------------------------------------------------

gsw_warn() {
  printf 'gemini_switcher[%s]: %s\n' "${GSW_PROFILE:-?}" "$*" >&2
}

# Move an unexpected entry out of the way without deleting it.
gsw_stray() {
  local path=$1 dest
  dest=$path.gsw-stray.$(date +%Y%m%d-%H%M%S).$$
  mv -- "$path" "$dest" || return 1
  gsw_warn "moved an unexpected entry aside: $dest"
}

# Make <profile>/<rel> a symlink to the shared directory <shared>/<rel>.
gsw_link_dir() {
  local rel=$1
  local link=$GSW_GEMINI_DIR/$rel target=$GSW_SHARED_ROOT/$rel
  mkdir -p -- "$target" "${link%/*}" || return 1
  if [[ -L $link ]]; then
    [[ "$(readlink -- "$link")" == "$target" ]] && return 0
    rm -f -- "$link" || return 1
  elif [[ -d $link ]]; then
    # A real directory: move its entries into the shared one, never
    # overwriting. Whatever cannot be moved is kept aside.
    find "$link" -mindepth 1 -maxdepth 1 -exec mv -n -t "$target" -- {} + 2>/dev/null
    if ! rmdir -- "$link" 2>/dev/null; then
      gsw_stray "$link" || return 1
    fi
  elif [[ -e $link ]]; then
    gsw_stray "$link" || return 1
  fi
  ln -s -- "$target" "$link"
}

# Make <profile>/<rel> a symlink to the shared file <shared>/<rel>.
# agy may replace such a symlink with a regular file (write to a temporary
# file, then rename). This function folds that file back into the shared one.
gsw_link_file() {
  local rel=$1 side
  local link=$GSW_GEMINI_DIR/$rel target=$GSW_SHARED_ROOT/$rel
  mkdir -p -- "${target%/*}" "${link%/*}" || return 1
  if [[ -L $link ]]; then
    if [[ "$(readlink -- "$link")" == "$target" && -e $target ]]; then
      return 0
    fi
    rm -f -- "$link" || return 1
  elif [[ -f $link ]]; then
    if [[ ! -e $target ]]; then
      # No shared file yet: this one becomes the shared file.
      mv -- "$link" "$target" || return 1
      for side in -wal -shm -journal; do
        if [[ -e $link$side ]]; then mv -- "$link$side" "$target$side"; fi
      done
    elif [[ $rel == *.json ]]; then
      # Whole-file JSON state: the newest file wins.
      if [[ $link -nt $target ]]; then
        mv -f -- "$link" "$target" || return 1
      else
        rm -f -- "$link" || return 1
      fi
    else
      # Databases are never overwritten. Keep the unexpected copy aside.
      gsw_stray "$link" || return 1
      for side in -wal -shm -journal; do
        if [[ -e $link$side ]]; then gsw_stray "$link$side"; fi
      done
    fi
  elif [[ -e $link ]]; then
    gsw_stray "$link" || return 1
  fi
  # Never leave a dangling symlink: if agy has not created the shared file
  # yet, agy creates it here and the next sync adopts it.
  [[ -e $target ]] || return 0
  ln -s -- "$target" "$link"
}

gsw_sync_links() {
  local rel rc=0
  for rel in "${GSW_SHARED_DIRS[@]}"; do
    if ! gsw_link_dir "$rel"; then
      gsw_warn "cannot link shared directory: $rel"
      rc=1
    fi
  done
  for rel in "${GSW_SHARED_FILES[@]}"; do
    if ! gsw_link_file "$rel"; then
      gsw_warn "cannot link shared file: $rel"
      rc=1
    fi
  done
  return "$rc"
}

gsw_wrapper_main() {
  local rc
  if [[ "$(uname -s)" != "Linux" ]]; then
    gsw_warn "Linux only: on this system agy does not separate accounts by directory."
    exit 1
  fi
  if ! command -v agy >/dev/null 2>&1; then
    gsw_warn "agy was not found in PATH."
    exit 127
  fi
  if [[ ! -d $GSW_GEMINI_DIR ]]; then
    gsw_warn "profile directory is missing: $GSW_GEMINI_DIR"
    gsw_warn "the profile was deleted or renamed; run gemini_switcher.sh (doctor)."
    exit 1
  fi
  if ! gsw_sync_links; then
    gsw_warn "shared conversation links are broken; not starting agy."
    exit 1
  fi
  # Fold shared files back in when agy ends, also after Ctrl-C or a hangup.
  trap 'gsw_sync_links' EXIT
  trap ':' INT
  trap 'exit 129' HUP
  trap 'exit 143' TERM
  command agy --gemini_dir "$GSW_GEMINI_DIR" "$@"
  rc=$?
  exit "$rc"
}

# -----------------------------------------------------------------------------
# Manager-only functions.
# -----------------------------------------------------------------------------

gsw_say() { printf '%s\n' "$*"; }
gsw_err() { printf 'ERROR: %s\n' "$*" >&2; }

# Ask one line. Result in GSW_ANSWER (trimmed). Returns 1 at end of input.
gsw_ask() {
  GSW_ANSWER=
  IFS= read -r -p "$1" GSW_ANSWER || return 1
  GSW_ANSWER=${GSW_ANSWER#"${GSW_ANSWER%%[![:space:]]*}"}
  GSW_ANSWER=${GSW_ANSWER%"${GSW_ANSWER##*[![:space:]]}"}
  return 0
}

gsw_write_default_config() {
  cat > "$GSW_CONFIG" <<'EOF'
# gemini_switcher config. This file is read as bash.
# After changing anything here, run "update" in gemini_switcher.sh so the
# wrapper scripts pick up the change.

# Directory where the profile commands (wrapper scripts) are written.
BIN_DIR=/usr/local/bin

# The data directory plain "agy" uses. Shared conversation data lives here.
SHARED_ROOT="$HOME/.gemini"

# Directories shared by every profile, relative to SHARED_ROOT.
SHARED_DIRS=(
  antigravity-cli/conversations
  antigravity-cli/presence
  antigravity-cli/brain
  antigravity-cli/annotations
)

# Single files shared by every profile, relative to SHARED_ROOT.
SHARED_FILES=(
  antigravity-cli/conversation_summaries.db
  antigravity-cli/cache/last_conversations.json
  antigravity-cli/cache/conversation_metadata.json
)
EOF
}

gsw_load_config() {
  local rel
  mkdir -p -- "$GSW_HOME" "$GSW_PROFILES" || { gsw_err "cannot create $GSW_HOME"; return 1; }
  chmod 700 -- "$GSW_HOME" "$GSW_PROFILES" 2>/dev/null
  if [[ ! -f $GSW_CONFIG ]]; then
    gsw_write_default_config || { gsw_err "cannot write $GSW_CONFIG"; return 1; }
  fi
  BIN_DIR=
  SHARED_ROOT=
  SHARED_DIRS=()
  SHARED_FILES=()
  # shellcheck disable=SC1090
  source "$GSW_CONFIG" || { gsw_err "cannot read $GSW_CONFIG"; return 1; }
  BIN_DIR=${BIN_DIR%/}
  SHARED_ROOT=${SHARED_ROOT%/}
  if [[ $BIN_DIR != /* ]]; then
    gsw_err "BIN_DIR in $GSW_CONFIG must be an absolute path."; return 1
  fi
  if [[ $SHARED_ROOT != /* ]]; then
    gsw_err "SHARED_ROOT in $GSW_CONFIG must be an absolute path."; return 1
  fi
  for rel in "${SHARED_DIRS[@]}" "${SHARED_FILES[@]}"; do
    if [[ -z $rel || $rel == /* || $rel == *..* || $rel == */ ]]; then
      gsw_err "invalid shared entry in $GSW_CONFIG: '$rel' (must be a relative path without '..')."
      return 1
    fi
  done
  GSW_SHARED_ROOT=$SHARED_ROOT
  GSW_SHARED_DIRS=("${SHARED_DIRS[@]}")
  GSW_SHARED_FILES=("${SHARED_FILES[@]}")
}

gsw_profile_names() {
  local d
  for d in "$GSW_PROFILES"/*/; do
    [[ -d $d ]] || continue
    d=${d%/}
    printf '%s\n' "${d##*/}"
  done
}

gsw_use_profile() {
  GSW_PROFILE=$1
  GSW_GEMINI_DIR=$GSW_PROFILES/$1/gemini
}

# Print the Google account stored in a token file. Never prints the token.
gsw_token_email() {
  [[ -s $1 ]] || return 1
  tr -d '\n' < "$1" 2>/dev/null |
    sed -n 's/.*"id_token_email"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

gsw_profile_note() {
  local meta=$GSW_PROFILES/$1/meta
  [[ -f $meta ]] || return 0
  sed -n 's/^note=//p' "$meta" | head -n 1
}

gsw_is_managed() {
  [[ -f $1 && ! -L $1 ]] || return 1
  LC_ALL=C head -n 5 -- "$1" 2>/dev/null | LC_ALL=C grep -qxF -- "# $GSW_MARKER"
}

gsw_header() {
  LC_ALL=C head -n 8 -- "$1" 2>/dev/null | sed -n "s/^# $2: //p" | head -n 1
}

# Print the full text of the wrapper script for profile $1.
gsw_render_wrapper() {
  local name=$1
  printf '#!/usr/bin/env bash\n'
  printf '# %s\n' "$GSW_MARKER"
  printf '# profile: %s\n' "$name"
  printf '# template_version: %s\n' "$GSW_TEMPLATE_VERSION"
  printf '# generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf '#\n'
  printf '# Runs agy with the private data directory of this profile.\n'
  printf '# Written by gemini_switcher.sh. Do not edit: "update" overwrites this file.\n'
  printf '\n'
  printf 'GSW_PROFILE=%q\n' "$name"
  printf 'GSW_GEMINI_DIR=%q\n' "$GSW_PROFILES/$name/gemini"
  printf 'GSW_SHARED_ROOT=%q\n' "$GSW_SHARED_ROOT"
  declare -p GSW_SHARED_DIRS GSW_SHARED_FILES
  printf '\n'
  declare -f gsw_warn gsw_stray gsw_link_dir gsw_link_file gsw_sync_links gsw_wrapper_main
  printf '\n'
  printf 'gsw_wrapper_main "$@"\n'
}

# Print one word: ok | missing | foreign | mismatch | outdated
gsw_wrapper_state() {
  local name=$1 f=$BIN_DIR/$1
  if [[ ! -e $f && ! -L $f ]]; then echo missing; return; fi
  if ! gsw_is_managed "$f"; then echo foreign; return; fi
  if [[ "$(gsw_header "$f" profile)" != "$name" ]]; then echo mismatch; return; fi
  if ! diff -q <(grep -v '^# generated: ' "$f") \
               <(gsw_render_wrapper "$name" | grep -v '^# generated: ') >/dev/null 2>&1; then
    echo outdated; return
  fi
  echo ok
}

gsw_write_wrapper() {
  local name=$1 dest=$BIN_DIR/$1 tmp
  if [[ -e $dest || -L $dest ]] && ! gsw_is_managed "$dest"; then
    gsw_err "$dest exists and was not written by gemini_switcher. It was left untouched."
    return 1
  fi
  tmp=$(mktemp "$BIN_DIR/.gsw-tmp.XXXXXX") || { gsw_err "cannot write into $BIN_DIR"; return 1; }
  if gsw_render_wrapper "$name" > "$tmp" && chmod 755 "$tmp" && mv -f -- "$tmp" "$dest"; then
    return 0
  fi
  rm -f -- "$tmp"
  gsw_err "cannot write $dest"
  return 1
}

# Remove BIN_DIR/<name> only if it is a wrapper of ours for this profile.
gsw_remove_wrapper() {
  local name=$1 f=$BIN_DIR/$1
  [[ -e $f || -L $f ]] || return 0
  if gsw_is_managed "$f" && [[ "$(gsw_header "$f" profile)" == "$name" ]]; then
    rm -f -- "$f"
  else
    gsw_err "$f was not written by gemini_switcher for '$name'. It was left untouched."
    return 1
  fi
}

gsw_remove_profile_dir() {
  local name=$1 dir=$GSW_PROFILES/$1
  [[ -n $name && $name != */* && $name != .* ]] || return 1
  [[ -d $dir && ! -L $dir ]] || return 0
  # rm does not follow the shared symlinks inside; shared data is not touched.
  rm -rf -- "$dir"
}

gsw_is_running() {
  command -v pgrep >/dev/null 2>&1 || return 1
  pgrep -f -- "--gemini_dir[= ]$GSW_PROFILES/$1/gemini( |\$)" >/dev/null 2>&1
}

gsw_require_bin_dir() {
  if [[ ! -d $BIN_DIR ]]; then
    gsw_err "BIN_DIR does not exist: $BIN_DIR"; return 1
  fi
  if [[ ! -w $BIN_DIR ]]; then
    gsw_err "BIN_DIR is not writable: $BIN_DIR (run this script as root)."; return 1
  fi
}

gsw_validate_new_name() {
  local name=$1 r kind
  if [[ ! $name =~ ^[A-Za-z][A-Za-z0-9_-]{0,31}$ ]]; then
    gsw_err "invalid name '$name'. Use 1-32 characters: letters, digits, '_' and '-', starting with a letter."
    return 1
  fi
  for r in "${GSW_RESERVED_NAMES[@]}"; do
    if [[ $name == "$r" ]]; then
      gsw_err "'$name' is a reserved name."; return 1
    fi
  done
  if [[ -e $GSW_PROFILES/$name ]]; then
    gsw_err "a profile named '$name' already exists."; return 1
  fi
  if [[ -e $BIN_DIR/$name || -L $BIN_DIR/$name ]]; then
    gsw_err "$BIN_DIR/$name already exists."; return 1
  fi
  if kind=$(type -t -- "$name" 2>/dev/null) && [[ -n $kind ]]; then
    gsw_err "'$name' already resolves as a command ($kind). Choose another name."
    return 1
  fi
}

# Show the profiles and ask for one. Result in GSW_PICK.
gsw_pick_profile() {
  local verb=$1 names=() n i=1
  GSW_PICK=
  mapfile -t names < <(gsw_profile_names)
  if (( ${#names[@]} == 0 )); then
    gsw_say "There are no profiles yet."
    return 1
  fi
  for n in "${names[@]}"; do
    printf '  %d) %s\n' "$i" "$n"
    i=$((i + 1))
  done
  gsw_ask "Profile to $verb (number or name, Enter to cancel): " || return 1
  [[ -n $GSW_ANSWER ]] || return 1
  if [[ $GSW_ANSWER =~ ^[0-9]+$ ]]; then
    i=$((10#$GSW_ANSWER))
    if (( i >= 1 && i <= ${#names[@]} )); then
      GSW_PICK=${names[i - 1]}
      return 0
    fi
  fi
  for n in "${names[@]}"; do
    if [[ $n == "$GSW_ANSWER" ]]; then GSW_PICK=$n; return 0; fi
  done
  gsw_err "no such profile: $GSW_ANSWER"
  return 1
}

# ----------------------------------------------------------------- list ------

gsw_action_list() {
  local names=() n email note account login state token
  mapfile -t names < <(gsw_profile_names)
  printf '\n%-22s %-34s %-6s %s\n' "COMMAND" "ACCOUNT" "LOGIN" "WRAPPER"
  token=$GSW_SHARED_ROOT/antigravity-cli/antigravity-oauth-token
  email=$(gsw_token_email "$token")
  login=no; [[ -s $token ]] && login=yes
  printf '%-22s %-34s %-6s %s\n' "agy (default)" "${email:--}" "$login" "-"
  for n in "${names[@]}"; do
    token=$GSW_PROFILES/$n/gemini/antigravity-cli/antigravity-oauth-token
    email=$(gsw_token_email "$token")
    note=$(gsw_profile_note "$n")
    login=no; [[ -s $token ]] && login=yes
    if [[ -n $email ]]; then
      account=$email
    elif [[ -n $note ]]; then
      account="note: $note"
    else
      account=-
    fi
    state=$(gsw_wrapper_state "$n")
    printf '%-22s %-34s %-6s %s\n' "$n" "$account" "$login" "$state"
  done
  printf '\n%d profile(s). Commands in %s, data in %s\n' "${#names[@]}" "$BIN_DIR" "$GSW_PROFILES"
  gsw_say "WRAPPER: ok = current; outdated = run 'update'; missing/foreign/mismatch = run 'doctor'."
}

# ------------------------------------------------------------------ add ------

gsw_action_add() {
  local name note dir
  gsw_require_bin_dir || return 1
  gsw_ask "New command name, e.g. agy_xyz (Enter to cancel): " || return 1
  [[ -n $GSW_ANSWER ]] || return 0
  name=$GSW_ANSWER
  gsw_validate_new_name "$name" || return 1
  note=
  if gsw_ask "Note shown in the list until you sign in, e.g. the account email (optional): "; then
    note=$GSW_ANSWER
  fi
  dir=$GSW_PROFILES/$name
  if ! mkdir -p -- "$dir/gemini/antigravity-cli"; then
    gsw_err "cannot create $dir"; return 1
  fi
  chmod 700 -- "$dir" "$dir/gemini"
  printf 'created=%s\nnote=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$note" > "$dir/meta"
  gsw_use_profile "$name"
  if ! gsw_sync_links; then
    gsw_err "cannot create the shared conversation links. Nothing was added."
    gsw_remove_profile_dir "$name"
    return 1
  fi
  if ! gsw_write_wrapper "$name"; then
    gsw_err "Nothing was added."
    gsw_remove_profile_dir "$name"
    return 1
  fi
  gsw_say "Added profile '$name'."
  gsw_say "  command : $BIN_DIR/$name"
  gsw_say "  data    : $dir/gemini"
  gsw_say "Run '$name' to sign in. It starts like agy on a new machine;"
  gsw_say "only the conversations are shared."
}

# ------------------------------------------------------------------ del ------

gsw_action_del() {
  local name
  gsw_require_bin_dir || return 1
  gsw_pick_profile "delete" || return 0
  name=$GSW_PICK
  if gsw_is_running "$name"; then
    gsw_err "'$name' is running. Exit that agy session first."; return 1
  fi
  gsw_say "This permanently deletes:"
  gsw_say "  $BIN_DIR/$name"
  gsw_say "  $GSW_PROFILES/$name   (login, settings, MCP config, skills, prompt history)"
  gsw_say "Shared conversations in $GSW_SHARED_ROOT are NOT deleted."
  gsw_ask "Type the profile name to confirm: " || return 1
  if [[ $GSW_ANSWER != "$name" ]]; then
    gsw_say "Not confirmed. Nothing was deleted."; return 0
  fi
  # Fold any pending shared file back before the profile goes away.
  gsw_use_profile "$name"
  [[ -d $GSW_GEMINI_DIR ]] && gsw_sync_links
  gsw_remove_wrapper "$name"
  if gsw_remove_profile_dir "$name"; then
    gsw_say "Deleted profile '$name'."
  else
    gsw_err "could not delete $GSW_PROFILES/$name"; return 1
  fi
}

# --------------------------------------------------------------- rename ------

gsw_action_rename() {
  local old new
  gsw_require_bin_dir || return 1
  gsw_pick_profile "rename" || return 0
  old=$GSW_PICK
  if gsw_is_running "$old"; then
    gsw_err "'$old' is running. Exit that agy session first."; return 1
  fi
  gsw_ask "New name for '$old' (Enter to cancel): " || return 1
  [[ -n $GSW_ANSWER ]] || return 0
  new=$GSW_ANSWER
  gsw_validate_new_name "$new" || return 1
  if ! mv -- "$GSW_PROFILES/$old" "$GSW_PROFILES/$new"; then
    gsw_err "cannot rename the profile directory. Nothing was changed."; return 1
  fi
  gsw_remove_wrapper "$old"
  gsw_use_profile "$new"
  gsw_sync_links
  if gsw_write_wrapper "$new"; then
    gsw_say "Renamed '$old' to '$new'. The login and all private data were kept."
  else
    gsw_err "the data was renamed to '$new' but its command was not written. Run 'update'."
    return 1
  fi
}

# --------------------------------------------------------------- update ------

gsw_action_update() {
  local names=() n done_count=0 fail_count=0
  gsw_require_bin_dir || return 1
  mapfile -t names < <(gsw_profile_names)
  if (( ${#names[@]} == 0 )); then
    gsw_say "There are no profiles yet."; return 0
  fi
  for n in "${names[@]}"; do
    gsw_use_profile "$n"
    if [[ ! -d $GSW_GEMINI_DIR ]]; then
      gsw_err "$n: data directory is missing: $GSW_GEMINI_DIR"
      fail_count=$((fail_count + 1)); continue
    fi
    if gsw_sync_links && gsw_write_wrapper "$n"; then
      gsw_say "updated: $BIN_DIR/$n"
      done_count=$((done_count + 1))
    else
      fail_count=$((fail_count + 1))
    fi
  done
  gsw_say "$done_count wrapper(s) rewritten, $fail_count failed. The agy binary was not touched."
}

# --------------------------------------------------------------- doctor ------

GSW_DOC_WARN=0
GSW_DOC_FAIL=0
gsw_doc() {
  case $1 in
    warn) GSW_DOC_WARN=$((GSW_DOC_WARN + 1)) ;;
    fail) GSW_DOC_FAIL=$((GSW_DOC_FAIL + 1)) ;;
  esac
  printf '[%-4s] %s\n' "$1" "$2"
}

gsw_doctor_links() {
  local name=$1 rel link target bad=0 strays
  for rel in "${GSW_SHARED_DIRS[@]}"; do
    link=$GSW_PROFILES/$name/gemini/$rel target=$GSW_SHARED_ROOT/$rel
    if [[ -L $link && "$(readlink -- "$link")" == "$target" && -d $target ]]; then
      continue
    fi
    gsw_doc fail "$name: shared directory is not linked: $rel (run 'update')"
    bad=1
  done
  for rel in "${GSW_SHARED_FILES[@]}"; do
    link=$GSW_PROFILES/$name/gemini/$rel target=$GSW_SHARED_ROOT/$rel
    if [[ -L $link && "$(readlink -- "$link")" == "$target" && -e $target ]]; then
      continue
    fi
    if [[ ! -e $target && ! -e $link && ! -L $link ]]; then
      gsw_doc info "$name: shared file not created by agy yet: $rel"
      continue
    fi
    gsw_doc warn "$name: shared file is not linked: $rel (repaired when '$name' next starts, or by 'update')"
    bad=1
  done
  (( bad == 0 )) && gsw_doc ok "$name: shared conversation links"
  strays=$(find "$GSW_PROFILES/$name" -maxdepth 4 -name '*.gsw-stray.*' 2>/dev/null | wc -l)
  if (( strays > 0 )); then
    gsw_doc warn "$name: $strays entr(y/ies) moved aside (*.gsw-stray.*) under $GSW_PROFILES/$name; inspect and delete them"
  fi
}

gsw_action_doctor() {
  local names=() n f p agy_path ver v state token email seen_emails=() e dup
  GSW_DOC_WARN=0
  GSW_DOC_FAIL=0
  gsw_say ""
  gsw_doc ok "system: $(uname -s)"

  agy_path=$(type -P agy 2>/dev/null)
  if [[ -n $agy_path ]]; then
    ver=$(command agy --version 2>/dev/null | head -n 1)
    gsw_doc ok "agy: $agy_path (version ${ver:-unknown})"
  else
    gsw_doc fail "agy was not found in PATH; the profile commands cannot start it"
  fi

  if [[ ! -d $BIN_DIR ]]; then
    gsw_doc fail "BIN_DIR does not exist: $BIN_DIR"
  elif [[ ! -w $BIN_DIR ]]; then
    gsw_doc fail "BIN_DIR is not writable: $BIN_DIR (run as root)"
  else
    gsw_doc ok "BIN_DIR: $BIN_DIR"
  fi
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) gsw_doc warn "BIN_DIR is not in PATH: the profile commands will not be found by name" ;;
  esac

  for v in GEMINI_API_KEY GOOGLE_API_KEY; do
    if [[ -n ${!v:-} ]]; then
      gsw_doc warn "$v is set in this shell; agy may use it instead of each profile's own login"
    fi
  done

  if [[ -d $GSW_SHARED_ROOT/antigravity-cli ]]; then
    gsw_doc ok "shared data: $GSW_SHARED_ROOT"
  else
    gsw_doc info "shared data directory does not exist yet: $GSW_SHARED_ROOT/antigravity-cli (created by the first profile)"
  fi
  token=$GSW_SHARED_ROOT/antigravity-cli/antigravity-oauth-token
  email=$(gsw_token_email "$token")
  [[ -n $email ]] && seen_emails+=("$email=agy (default)")

  mapfile -t names < <(gsw_profile_names)
  (( ${#names[@]} == 0 )) && gsw_doc info "no profiles yet"
  for n in "${names[@]}"; do
    if [[ ! -d $GSW_PROFILES/$n/gemini ]]; then
      gsw_doc fail "$n: data directory is missing: $GSW_PROFILES/$n/gemini"
      continue
    fi
    state=$(gsw_wrapper_state "$n")
    case $state in
      ok)       gsw_doc ok   "$n: wrapper $BIN_DIR/$n" ;;
      outdated) gsw_doc warn "$n: wrapper differs from the current template or config (run 'update')" ;;
      missing)  gsw_doc fail "$n: wrapper is missing: $BIN_DIR/$n (run 'update')" ;;
      foreign)  gsw_doc fail "$n: $BIN_DIR/$n exists but was not written by gemini_switcher" ;;
      mismatch) gsw_doc fail "$n: $BIN_DIR/$n belongs to another profile" ;;
    esac
    token=$GSW_PROFILES/$n/gemini/antigravity-cli/antigravity-oauth-token
    if [[ -s $token ]]; then
      email=$(gsw_token_email "$token")
      gsw_doc ok "$n: signed in${email:+ as $email}"
      if [[ -n $email ]]; then
        dup=
        for e in "${seen_emails[@]}"; do
          [[ ${e%%=*} == "$email" ]] && dup=${e#*=}
        done
        if [[ -n $dup ]]; then
          gsw_doc warn "$n: same Google account as '$dup' ($email)"
        fi
        seen_emails+=("$email=$n")
      fi
    else
      gsw_doc info "$n: not signed in yet (run '$n')"
    fi
    gsw_doctor_links "$n"
  done

  # Wrappers in BIN_DIR whose profile no longer exists.
  if [[ -d $BIN_DIR ]]; then
    for f in "$BIN_DIR"/*; do
      gsw_is_managed "$f" || continue
      p=$(gsw_header "$f" profile)
      if [[ -z $p || ! -d $GSW_PROFILES/$p || ${f##*/} != "$p" ]]; then
        gsw_doc warn "orphan wrapper: $f (profile '${p:-?}' does not exist); delete this file by hand"
      fi
    done
  fi

  gsw_say ""
  gsw_say "doctor: $GSW_DOC_FAIL failure(s), $GSW_DOC_WARN warning(s). Nothing was changed."
}

# ----------------------------------------------------------------- menu ------

gsw_menu() {
  cat <<EOF

gemini_switcher - agy profiles
  1) list      show all profiles
  2) add       create a new profile command
  3) del       delete a profile
  4) rename    rename a profile command
  5) update    rewrite all wrapper scripts
  6) doctor    check the setup (changes nothing)
  q) quit
EOF
}

gsw_main() {
  if (( $# > 0 )); then
    gsw_err "this script takes no arguments. Run: bash gemini_switcher.sh"
    exit 2
  fi
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    gsw_err "bash 4.4 or newer is required (this is $BASH_VERSION)."
    exit 1
  fi
  if [[ "$(uname -s)" != "Linux" ]]; then
    gsw_err "Linux only. On macOS agy keeps its login in the keychain, so profiles would all use the same account."
    exit 1
  fi
  gsw_load_config || exit 1
  gsw_action_list
  while true; do
    gsw_menu
    gsw_ask "choice: " || break
    case ${GSW_ANSWER,,} in
      1|list|ls)        gsw_action_list ;;
      2|add)            gsw_action_add ;;
      3|del|delete|rm)  gsw_action_del ;;
      4|rename|mv)      gsw_action_rename ;;
      5|update)         gsw_action_update ;;
      6|doctor)         gsw_action_doctor ;;
      q|quit|exit)      break ;;
      '')               ;;
      *)                gsw_err "unknown choice: $GSW_ANSWER" ;;
    esac
  done
}

gsw_main "$@"
