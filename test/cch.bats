#!/usr/bin/env bats

load test_helper

# macOS bash 3.2 does not stop on a failed [[ ]] under set -e, so each check ends with || false

@test "lists conversations newest first with directory and title" {
  old=$(new_session "$HOME/workspace/api" "hello")
  add_title "$old" "Older conversation"
  set_age "$old" 60
  new=$(new_session "$HOME/workspace/web" "hello")
  add_title "$new" "Newer conversation"
  set_age "$new" 5

  run "$CCH" -p
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"~/workspace/web"*"Newer conversation"* ]] || false
  [[ "${lines[1]}" == *"~/workspace/api"*"Older conversation"* ]] || false
}

@test "a conversation without a title is shown as untitled" {
  new_session "$HOME/workspace/api" "hello" > /dev/null

  run "$CCH" -p
  [[ "$output" == *"(untitled)"* ]] || false
}

@test "a title set with /rename wins over the generated title" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_title "$f" "Generated title"
  add_custom_title "$f" "My own title"

  run "$CCH" -p
  [[ "$output" == *"My own title"* ]] || false
  [[ "$output" != *"Generated title"* ]] || false
}

@test "titles with quotes and backslashes are shown as written" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_custom_title "$f" 'Fix "login" in C:\Users'

  run "$CCH" -p
  [[ "$output" == *'Fix "login" in C:\Users'* ]] || false
}

@test "long wide-character titles are truncated and the cost column stays aligned" {
  a=$(new_session "$HOME/workspace/api" "hello")
  add_title "$a" "とても長い日本語の題名がここに入っていて四十マスを超えてしまう会話"
  add_reply "$a" msg_a 100000 0
  b=$(new_session "$HOME/workspace/web" "hello")
  add_title "$b" "Short"
  add_reply "$b" msg_b 100000 0

  run "$CCH" -p
  [[ "$output" == *"…"* ]] || false
  # Display column where "$" starts, counting wide characters as 2
  columns=$(echo "$output" | perl -CSD -ne '
    my ($before) = /^(.*?)\$/ or next;
    my $w = 0; $w += /\p{Ea=W}|\p{Ea=F}/ ? 2 : 1 for split //, $before; print "$w\n"' | sort -u | wc -l)
  [ "$columns" -eq 1 ]
}

@test "cost counts each reply once and includes subagents" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_title "$f" "Costly"
  # 100k input * $0.000001 + 10k output * $0.00001 = $0.20, written twice as Claude Code does per content block
  add_reply "$f" msg_1 100000 10000
  add_reply "$f" msg_1 100000 10000
  mkdir -p "${f%.jsonl}/subagents"
  add_reply "${f%.jsonl}/subagents/agent-1.jsonl" msg_sub 0 10000

  run "$CCH" -p
  [[ "$output" == *'$0.30'* ]] || false
}

@test "context size is the input of the latest reply" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_reply "$f" msg_1 50000 0
  add_reply "$f" msg_2 163000 0

  run "$CCH" -p
  [[ "$output" == *"163K"* ]] || false
}

@test "unchanged files are served from the cache, changed files are read again" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_title "$f" "Before"
  set_age "$f" 10
  "$CCH" -p > /dev/null

  # Change the content but keep mtime: the cached title must be used
  ref="$BATS_TEST_TMPDIR/ref"
  touch -r "$f" "$ref"
  add_title "$f" "After"
  touch -r "$ref" "$f"
  run "$CCH" -p
  [[ "$output" == *"Before"* ]] || false

  touch "$f"
  run "$CCH" -p
  [[ "$output" == *"After"* ]] || false
}

@test "a search word lists only conversations that contain it" {
  a=$(new_session "$HOME/workspace/api" "talk about pineapples")
  add_title "$a" "Fruit"
  b=$(new_session "$HOME/workspace/web" "talk about trains")
  add_title "$b" "Trains"

  run "$CCH" -p pineapples
  [[ "$output" == *"Fruit"* ]] || false
  [[ "$output" != *"Trains"* ]] || false
}

@test "reloading the list searches the content only in the content field" {
  a=$(new_session "$HOME/workspace/api" "talk about pineapples")
  add_title "$a" "Fruit"
  b=$(new_session "$HOME/workspace/web" "talk about trains")
  add_title "$b" "Trains"

  # fzf passes the prompt and the query to reload commands
  run env FZF_PROMPT="content> " FZF_QUERY=pineapples "$CCH" __list
  [[ "$output" == *"Fruit"* ]] || false
  [[ "$output" != *"Trains"* ]] || false

  run env FZF_PROMPT="title> " FZF_QUERY=pineapples "$CCH" __list
  [[ "$output" == *"Fruit"* ]] || false
  [[ "$output" == *"Trains"* ]] || false
}

@test "a search word in tool output or pasted image data does not count" {
  a=$(new_session "$HOME/workspace/api" "look at this")
  add_title "$a" "Only in tool output"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"PINEAPPLE"}]}}' >> "$a"
  b=$(new_session "$HOME/workspace/web" "look at this")
  add_title "$b" "Only in an image"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"xxPINEAPPLExx"}}]}}' >> "$b"
  c=$(new_session "$HOME/workspace/cli" "and this")
  add_title "$c" "In a reply"
  add_reply "$c" msg_1 10 10 "PINEAPPLE it is"
  d=$(new_session "$HOME/workspace/ml" "and this")
  add_title "$d" "PINEAPPLE in the title"

  e=$(new_session "$HOME/workspace/doc" "and this")
  add_title "$e" "Only in a long paste"
  long=$(printf 'x%.0s' $(seq 10000))
  jq -cn --arg t "PINEAPPLE $long" '{type: "user", message: {role: "user", content: [{type: "text", text: $t}]}}' >> "$e"
  f=$(new_session "$HOME/workspace/img" "and this")
  add_title "$f" "Next to an image"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"see PINEAPPLE"},{"type":"image","source":{"type":"base64","data":"xxPINEAPPLExx"}}]}}' >> "$f"

  run "$CCH" -p PINEAPPLE
  [[ "$output" == *"Next to an image"* ]] || false
  [[ "$output" != *"Only in a long paste"* ]] || false
  [[ "$output" == *"In a reply"* ]] || false
  [[ "$output" == *"PINEAPPLE in the title"* ]] || false
  [[ "$output" != *"Only in tool output"* ]] || false
  [[ "$output" != *"Only in an image"* ]] || false
}

@test "summarize sends only the dialogue and normalizes the reply to at most 3 bullets" {
  f=$(new_session "$HOME/workspace/api" "please fix the bug")
  add_reply "$f" msg_1 10 10 "fixed it"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"SECRET TOOL OUTPUT"}]}}' >> "$f"
  export CLAUDE_STUB_OUTPUT='1. first\n\n- second\n* third\n• fourth\n'

  run "$CCH" summarize
  [ "$status" -eq 0 ]
  grep -q "U: please fix the bug" "$CLAUDE_STUB_LOG"
  grep -q "A: fixed it" "$CLAUDE_STUB_LOG"
  run grep -q "SECRET TOOL OUTPUT" "$CLAUDE_STUB_LOG"
  [ "$status" -ne 0 ]

  summary="$CCH_CACHE_DIR/summaries/en/$(basename "$f" .jsonl).txt"
  [ "$(cat "$summary")" = "$(printf -- '- first\n- second\n- third')" ]
}

@test "summarize skips conversations whose summary is up to date" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_reply "$f" msg_1 10 10 "hi"
  set_age "$f" 10
  export CLAUDE_STUB_OUTPUT='- done\n'
  "$CCH" summarize > /dev/null
  rm -f "$CLAUDE_STUB_LOG"

  run "$CCH" summarize
  [[ "$output" == *"No conversations need summarizing"* ]] || false
  [ ! -f "$CLAUDE_STUB_LOG" ]
}

@test "summarize 0 does nothing" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_reply "$f" msg_1 10 10 "hi"

  run "$CCH" summarize 0
  [ ! -f "$CLAUDE_STUB_LOG" ]
}

@test "missing dependencies are reported and cch exits" {
  # A PATH with the basics and the claude stub, but without fzf, jq and rg
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for c in bash env cat sed tr; do ln -s "$(command -v "$c")" "$bin/$c"; done
  ln -s "$BATS_TEST_DIRNAME/stubs/claude" "$bin/claude"

  PATH="$bin" run "$CCH" -p < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"cch needs: fzf jq rg"* ]] || false
  # No package manager is on this PATH, so only the package names are given
  [[ "$output" == *"(packages: fzf jq ripgrep)"* ]] || false
}

@test "help is shown in the chosen language" {
  run env CCH_LANG=en "$CCH" help
  [[ "${lines[0]}" == "Usage: cch"* ]] || false
  run env CCH_LANG=ja "$CCH" --help
  [[ "${lines[0]}" == "使い方: cch"* ]] || false
  run env CCH_LANG=zh "$CCH" -h
  [[ "${lines[0]}" == "用法: cch"* ]] || false
}

@test "an unknown language falls back to English" {
  run env CCH_LANG=xx "$CCH" help
  [[ "${lines[0]}" == "Usage: cch"* ]] || false
}

# Last prompt in the preview: only what the user actually wrote

add_line() { echo "$2" >> "$1"; }

last_prompt_of() {
  "$CCH" __preview "$1" "$HOME/workspace/api" | sed -n '/^\[Last prompt\]$/,$p' | tail -n +2
}

@test "last prompt skips tool results, injected notes and compact summaries" {
  f=$(new_session "$HOME/workspace/api" 'He said "hi" in C:\Temp')
  add_line "$f" '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"tool output"}]}}'
  add_line "$f" '{"type":"user","isMeta":true,"message":{"role":"user","content":"meta note"}}'
  add_line "$f" '{"type":"user","message":{"role":"user","content":"<task-notification>done</task-notification>"}}'
  add_line "$f" '{"type":"user","message":{"role":"user","content":"<bash-stdout>ok</bash-stdout>"}}'
  add_line "$f" '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"}}'
  add_line "$f" '{"type":"last-prompt","lastPrompt":"stale record"}'

  run last_prompt_of "$f"
  [ "$output" = 'He said "hi" in C:\Temp' ]
}

@test "last prompt keeps line breaks and messages that start with an unknown tag" {
  f=$(new_session "$HOME/workspace/api" "first")
  add_line "$f" '{"type":"user","message":{"role":"user","content":"<div> is not rendered\nsecond line"}}'

  run last_prompt_of "$f"
  [ "$output" = "$(printf '<div> is not rendered\nsecond line')" ]
}

@test "last prompt shows the user's own words around pasted text, or the paste alone" {
  f=$(new_session "$HOME/workspace/api" "first")
  add_line "$f" '{"type":"user","message":{"role":"user","content":"<pasted_content id=\"1\">\nlong pasted text\n</pasted_content id=\"1\">\n\nis this right?"}}'
  run last_prompt_of "$f"
  [ "$output" = "is this right?" ]

  add_line "$f" '{"type":"user","message":{"role":"user","content":"<pasted_content id=\"2\">only a paste</pasted_content id=\"2\">"}}'
  run last_prompt_of "$f"
  [ "$output" = "only a paste" ]
}

@test "last prompt includes messages sent while Claude was working" {
  f=$(new_session "$HOME/workspace/api" "first")
  add_line "$f" '{"type":"attachment","attachment":{"type":"queued_command","prompt":"sent mid-turn"}}'

  run last_prompt_of "$f"
  [ "$output" = "sent mid-turn" ]
}

@test "last prompt includes text sent together with an image" {
  f=$(new_session "$HOME/workspace/api" "first")
  add_line "$f" '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Image #1] look at this"},{"type":"image","source":{}}]}}'
  add_line "$f" '{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"[Image: source: /tmp/x.png]"}]}}'

  run last_prompt_of "$f"
  [ "$output" = "[Image #1] look at this" ]
}

@test "summarize all goes past the default limit of 20" {
  for i in $(seq 1 22); do
    f=$(new_session "$HOME/workspace/api" "message $i")
    add_reply "$f" "msg_$i" 10 10 "reply $i"
  done
  export CLAUDE_STUB_OUTPUT='- done\n'

  run "$CCH" summarize all
  [ "$status" -eq 0 ]
  [ "$(ls "$CCH_CACHE_DIR/summaries/en" | wc -l | tr -d ' ')" -eq 22 ]
}

@test "summarize rejects a count that is neither a number nor all" {
  run "$CCH" summarize lots
  [ "$status" -eq 1 ]
  [[ "$output" == *"number or all"* ]] || false
}

# Summarize from the list (ctrl-s)

make_unsummarized() {
  local i f
  for i in $(seq 1 "$1"); do
    f=$(new_session "$HOME/workspace/api" "message $i")
    add_reply "$f" "msg_$i" 10 10 "reply $i"
  done
  export CLAUDE_STUB_OUTPUT='- done\n'
}

summary_count() {
  ls "$CCH_CACHE_DIR/summaries/en" 2>/dev/null | wc -l | tr -d ' '
}

@test "ctrl-s asks with the count and model, and Enter summarizes the latest 20" {
  make_unsummarized 22
  run "$CCH" __summarize <<< ""
  [[ "$output" == *"22 conversations"*"(model: Haiku 4.5)"* ]] || false
  [ "$(summary_count)" -eq 20 ]
}

@test "ctrl-s summarizes everything only when all is typed out" {
  make_unsummarized 22
  run "$CCH" __summarize <<< "ALL"
  [ "$(summary_count)" -eq 22 ]
}

@test "ctrl-s does nothing for any other answer" {
  make_unsummarized 3
  run "$CCH" __summarize <<< "a"
  [ "$(summary_count)" -eq 0 ]
  [ ! -f "$CLAUDE_STUB_LOG" ]
}

@test "summaries are made with the pinned Haiku model" {
  make_unsummarized 1
  "$CCH" summarize > /dev/null
  [[ "$(cat "$CLAUDE_STUB_ARGS")" == *"--model claude-haiku-4-5"* ]] || false
}

@test "a failed run is not saved as a summary, although claude exits 0" {
  make_unsummarized 1
  export CLAUDE_STUB_ERROR=1
  run "$CCH" summarize
  [ "$status" -eq 0 ]
  [[ "$output" == *"failed to summarize"* ]] || false
  [ "$(summary_count)" -eq 0 ]
}

@test "Ctrl-C stops summarizing instead of going on to the next conversation" {
  make_unsummarized 3
  export CLAUDE_STUB_READY="$BATS_TEST_TMPDIR/ready"
  # Run in its own process group, like a job in a terminal, so Ctrl-C reaches cch and claude together.
  # Background jobs start with SIGINT ignored, so restore the default first
  perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' "$CCH" summarize > /dev/null 2>&1 &
  pid=$!
  for _ in $(seq 100); do [ -f "$CLAUDE_STUB_READY" ] && break; sleep 0.1; done
  kill -INT -- -"$pid"
  rc=0
  wait "$pid" || rc=$?
  [ "$rc" -eq 130 ]
  [ "$(wc -l < "$CLAUDE_STUB_ARGS.calls" | tr -d ' ')" -eq 1 ]
  [ "$(summary_count)" -eq 0 ]
}

@test "without a terminal, summarize prints one line per conversation instead of a bar" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_title "$f" "Payment retries"
  add_reply "$f" msg_1 10 10 "hi"
  export CLAUDE_STUB_OUTPUT='- done\n'

  run "$CCH" summarize
  [ "$output" = "[1/1] Payment retries" ]
}

# Delete (ctrl-x)

@test "delete moves the conversation, its directory and summary to the Trash on y" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_title "$f" "To be deleted"
  id=$(basename "$f" .jsonl)
  mkdir -p "${f%.jsonl}/subagents"
  mkdir -p "$CCH_CACHE_DIR/summaries/en"
  echo "- summary" > "$CCH_CACHE_DIR/summaries/en/$id.txt"
  "$CCH" -p > /dev/null

  run "$CCH" __delete "$f" <<< "y"
  [ ! -e "$f" ]
  [ -e "$TRASH_DIR/$id.jsonl" ]
  [ -d "$TRASH_DIR/$id" ]
  [ -e "$TRASH_DIR/$id.txt" ]
  run "$CCH" -p
  [[ "$output" != *"To be deleted"* ]] || false
}

@test "delete also confirms on Enter" {
  f=$(new_session "$HOME/workspace/api" "hello")
  run "$CCH" __delete "$f" <<< ""
  [ ! -e "$f" ]
  [ -e "$TRASH_DIR/$(basename "$f")" ]
}

@test "delete keeps everything for any other key, including Esc" {
  f=$(new_session "$HOME/workspace/api" "hello")
  for answer in "n" $'\e' "x"; do
    run "$CCH" __delete "$f" <<< "$answer"
    [ -e "$f" ]
  done
  [ ! -d "$TRASH_DIR" ]
}

# Preview header

@test "preview shortens the directory and hides HEAD" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_line "$f" '{"type":"assistant","gitBranch":"HEAD","message":{"id":"m","content":[]}}'

  run "$CCH" __preview "$f" "$HOME/workspace/api"
  [ "${lines[0]}" = "dir    : ~/workspace/api" ]
  [[ "$output" != *"branch"* ]] || false
}

@test "preview lists the latest 5 PRs without duplicates" {
  f=$(new_session "$HOME/workspace/api" "hello")
  for n in 1 2 3 4 5 6; do
    add_line "$f" "{\"type\":\"pr-link\",\"prUrl\":\"https://github.com/example/api/pull/$n\"}"
  done
  add_line "$f" '{"type":"pr-link","prUrl":"https://github.com/example/api/pull/2"}'

  run "$CCH" __preview "$f" "$HOME/workspace/api"
  prs=$(echo "$output" | sed -n 's#^PR     : .*/pull/##p' | tr '\n' ' ')
  [ "$prs" = "2 6 5 4 3 " ]
}

@test "preview shows the summary under a heading in the chosen language" {
  f=$(new_session "$HOME/workspace/api" "hello")
  mkdir -p "$CCH_CACHE_DIR/summaries/ja"
  echo "・要約です" > "$CCH_CACHE_DIR/summaries/ja/$(basename "$f" .jsonl).txt"

  CCH_LANG=ja run "$CCH" __preview "$f" "$HOME/workspace/api"
  [[ "$output" == *$'[要約]\n・要約です'* ]] || false
}

# Settings and environment

@test "the saved language is used when CCH_LANG is not set" {
  mkdir -p "$XDG_CONFIG_HOME/cch"
  echo zh > "$XDG_CONFIG_HOME/cch/lang"
  unset CCH_LANG

  run "$CCH" help
  [[ "${lines[0]}" == "用法: cch"* ]] || false
}

@test "cch exits with a link when Claude Code is not installed" {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for c in bash env cat sed tr fzf jq rg; do ln -s "$(command -v "$c")" "$bin/$c"; done

  PATH="$bin" run "$CCH" -p < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"cch needs Claude Code"*"docs.claude.com"* ]] || false
}

@test "a model missing from the price table costs nothing instead of failing" {
  f=$(new_session "$HOME/workspace/api" "hello")
  add_title "$f" "Unknown model"
  add_line "$f" '{"type":"assistant","message":{"id":"m1","model":"some-future-model","content":[],"usage":{"input_tokens":1000,"output_tokens":1000}}}'

  run "$CCH" -p
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unknown model"*'$0.00'* ]] || false
}

@test "inside fzf's preview, PR URLs are orange hyperlinks" {
  f=$(new_session "$HOME/workspace/api" "hello")
  url="https://github.com/example/api/pull/7"
  add_line "$f" "{\"type\":\"pr-link\",\"prUrl\":\"$url\"}"

  FZF_PREVIEW_COLUMNS=80 run "$CCH" __preview "$f" "$HOME/workspace/api"
  expected=$(printf 'PR     : \e]8;;%s\e\\\e[1;38;2;255;150;100m%s\e[0m\e]8;;\e\\' "$url" "$url")
  [[ "$output" == *"$expected"* ]] || false
}

@test "--version prints the version without needing any dependency" {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -s "$(command -v bash)" "$bin/bash"
  PATH="$bin" run "$CCH" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^cch\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || false
}

# fake_fzf <version line>: puts an fzf that only reports this version first on PATH
fake_fzf() {
  mkdir -p "$BATS_TEST_TMPDIR/fakefzf"
  printf '#!/bin/bash\necho "%s"\n' "$1" > "$BATS_TEST_TMPDIR/fakefzf/fzf"
  chmod +x "$BATS_TEST_TMPDIR/fakefzf/fzf"
  export PATH="$BATS_TEST_TMPDIR/fakefzf:$PATH"
}

@test "an fzf older than 0.58 is reported and cch exits" {
  fake_fzf "0.44.1 (debian)"
  run "$CCH" -p
  [ "$status" -eq 1 ]
  [[ "$output" == *"cch needs fzf 0.58 or later (found 0.44.1)"* ]] || false
}

@test "fzf 0.58 or later, or a version that cannot be read, is accepted" {
  new_session /work/api "hello" > /dev/null
  for v in "0.58.0 (abc123)" "1.0.0" "dev"; do
    fake_fzf "$v"
    run "$CCH" -p
    [ "$status" -eq 0 ]
  done
}

@test "preview wraps a long prompt at 80 columns without splitting wide characters" {
  # 60 wide characters are 120 columns: two lines of 40 and 20, all valid UTF-8
  f=$(new_session "$HOME/workspace/api" "$(printf 'あ%.0s' $(seq 60))")
  run last_prompt_of "$f"
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$(printf 'あ%.0s' $(seq 40))" ]
  [ "${lines[1]}" = "$(printf 'あ%.0s' $(seq 20))" ]
}
