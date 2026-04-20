#!/usr/bin/env nu
# generate-ctx-docs.nu — Write .ctx/HANDOFF.md and .ctx/HANDOVER.md from HANDOFF YAML.
#
# Usage:
#   generate-ctx-docs.nu --handoff <path> [--state <path>] [--ctx <dir>]
#
# Arguments:
#   --handoff  Path to HANDOFF.<name>.<base>.yaml
#   --state    Path to HANDOFF.<name>.<base>.state.yaml (optional)
#   --ctx      Output directory (default: directory containing the handoff file)

def main [
    --handoff: string   # Path to HANDOFF YAML
    --state: string = ""  # Path to state YAML (optional)
    --ctx: string = ""    # Output directory (default: handoff file's parent dir)
] {
    if ($handoff | is-empty) {
        error make { msg: "--handoff is required" }
    }
    if not ($handoff | path exists) {
        error make { msg: $"file not found: ($handoff)" }
    }

    let ctx_dir = if ($ctx | is-empty) {
        $handoff | path dirname
    } else {
        $ctx
    }

    mkdir $ctx_dir

    let hdata = open $handoff

    let project = $hdata | get -i project | default ""
    let updated = $hdata | get -i updated | default ""
    let notes   = $hdata | get -i notes   | default ""
    let items   = $hdata | get -i items   | default []
    let log     = $hdata | get -i log     | default []

    # State fields
    let state = if ($state | is-not-empty) and ($state | path exists) {
        open $state
    } else {
        {}
    }
    let branch = $state | get -i branch | default "unknown"
    let build  = $state | get -i build  | default "unknown"
    let tests  = $state | get -i tests  | default "unknown"

    # -------------------------------------------------------------------------
    # Generate .ctx/HANDOFF.md
    # -------------------------------------------------------------------------

    let handoff_md = [$ctx_dir "HANDOFF.md"] | path join

    let header = $"# Handoff — ($project) \(($updated)\)\n\n**Branch:** ($branch) | **Build:** ($build) | **Tests:** ($tests)\n"

    let notes_block = if ($notes | is-not-empty) and ($notes != "null") {
        $"\n($notes)\n"
    } else {
        ""
    }

    let items_header = "\n## Items\n\n| ID | P | Status | Title |\n|---|---|---|---|\n"

    # Sort items: P0 open, P1 open, P2 open, then blocked (same prio order)
    let sorted_items = $items | sort-by { |it|
        let raw_p = $it | get -i priority | default "P2" | str replace -r '^P' "" | into int
        let ord = if ($it | get -i status | default "open") == "blocked" { 10 } else { 0 }
        $raw_p + $ord
    }

    let items_rows = $sorted_items | each { |it|
        let id     = $it | get -i id       | default "-"
        let p      = $it | get -i priority | default "-"
        let status = $it | get -i status   | default "open"
        let title  = $it | get -i name     | default "-"
        $"| ($id) | ($p) | ($status) | ($title) |"
    } | str join "\n"

    let log_header = "\n\n## Log\n\n"

    let log_rows = $log | first ([$log 5] | math min) | each { |entry|
        let date    = $entry | get -i date    | default "-"
        let summary = $entry | get -i summary | default "-"
        let commits = $entry | get -i commits | default []
        let shas = $commits | each { |c| $c | get -i sha | default "" } | where { |s| $s | is-not-empty } | str join ", "
        if ($shas | is-not-empty) {
            $"- ($date): ($summary) [($shas)]"
        } else {
            $"- ($date): ($summary)"
        }
    } | str join "\n"

    let handoff_content = [$header $notes_block $items_header $items_rows $log_header $log_rows "\n"] | str join ""

    $handoff_content | save --force $handoff_md
    print $"wrote: ($handoff_md)"

    # -------------------------------------------------------------------------
    # Generate .ctx/HANDOVER.md
    # -------------------------------------------------------------------------

    let handover_md = [$ctx_dir "HANDOVER.md"] | path join

    let hov_header = $"# Handover — ($project)\n\n_Generated: ($updated)_\n\n"

    let flow_lines = $items | each { |it|
        let id     = $it | get -i id       | default "-"
        let p      = $it | get -i priority | default "-"
        let status = $it | get -i status   | default "open"
        let title  = $it | get -i name     | default "-"
        let deps   = $it | get -i depends_on | default []

        let sym = match $status {
            "open"    => "[ ]",
            "blocked" => "[!]",
            "done"    => "[x]",
            _         => "[?]",
        }

        let dep_line = if ($deps | length) > 0 {
            let dep_str = $deps | str join ", "
            $"\n       depends: ($dep_str)"
        } else {
            ""
        }

        $"  ($sym) ($p) ($id) — ($title)($dep_line)"
    } | str join "\n"

    let flow_block = $"## Item Flow\n\n```\n($flow_lines)\n```\n\n"

    let legend = "## Legend\n\n```\n  [ ]  open\n  [!]  blocked\n  [x]  done\n  P0   critical | P1 high | P2 normal\n```\n\n"

    let session_lines = $log | first ([$log 5] | math min) | each { |entry|
        let s       = $entry | get -i session | default "-"
        let date    = $entry | get -i date    | default "-"
        let summary = $entry | get -i summary | default "-"
        $"  s($s)  ($date)  ($summary)"
    } | str join "\n"

    let sessions_block = $"## Recent Sessions\n\n```\n($session_lines)\n```\n"

    let handover_content = [$hov_header $flow_block $legend $sessions_block] | str join ""

    $handover_content | save --force $handover_md
    print $"wrote: ($handover_md)"
}
