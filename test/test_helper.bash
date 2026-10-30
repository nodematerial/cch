# Shared setup and helpers to build fake Claude Code conversation files

# Used by the tests in cch.bats
# shellcheck disable=SC2034
CCH="$BATS_TEST_DIRNAME/../cch"

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  export CCH_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export CCH_LANG=en
  export CLAUDE_STUB_LOG="$BATS_TEST_TMPDIR/claude-input.txt"
  export CLAUDE_STUB_ARGS="$BATS_TEST_TMPDIR/claude-args.txt"
  export TRASH_DIR="$BATS_TEST_TMPDIR/trash"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects" "$CCH_CACHE_DIR"
  # A fresh price table keeps cch from downloading one
  cp "$BATS_TEST_DIRNAME/fixtures/prices.json" "$CCH_CACHE_DIR/prices.json"
}

# new_session <cwd> <first prompt> -> prints the path of the new conversation file
new_session() {
  local cwd="$1" prompt="$2" id dir
  id=$(uuidgen | tr '[:upper:]' '[:lower:]')
  dir="${cwd//[\/.]/-}"
  dir="$CLAUDE_CONFIG_DIR/projects/$dir"
  mkdir -p "$dir"
  jq -cn --arg cwd "$cwd" --arg id "$id" --arg p "$prompt" \
    '{type: "user", cwd: $cwd, sessionId: $id, gitBranch: "main", message: {role: "user", content: $p}}' \
    > "$dir/$id.jsonl"
  echo "$dir/$id.jsonl"
}

# add_reply <file> <message id> <input tokens> <output tokens> [reply text]
add_reply() {
  jq -cn --arg id "$2" --argjson in "$3" --argjson out "$4" --arg t "${5:-ok}" \
    '{type: "assistant", requestId: "req_\($id)", message: {id: $id, model: "test-model", role: "assistant",
      content: [{type: "text", text: $t}],
      usage: {input_tokens: $in, output_tokens: $out, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}' \
    >> "$1"
}

add_title() {
  jq -cn --arg t "$2" '{type: "ai-title", aiTitle: $t}' >> "$1"
}

add_custom_title() {
  jq -cn --arg t "$2" '{type: "custom-title", customTitle: $t}' >> "$1"
}

# set_age <file> <minutes ago>
set_age() {
  touch -t "$(date -v-"$2"M '+%Y%m%d%H%M.%S')" "$1"
}
