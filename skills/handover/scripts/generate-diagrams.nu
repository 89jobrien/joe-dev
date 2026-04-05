#!/usr/bin/env nu
# generate-diagrams.nu — emit Mermaid diagram blocks from a HANDOFF yaml file.
#
# Usage:
#   nu generate-diagrams.nu --handoff <path-to-HANDOFF.*.yaml> [--diagram <name>]
#
# Diagrams:
#   dependency  — inter-item dependency graph (gate: items must have deps)
#   burn        — pie chart of item status distribution (gate: ≥3 items)
#   velocity    — bar chart of items completed per date (gate: ≥2 log entries, ≥1 completed)
#   hotspots    — bar chart of most-touched files (gate: ≥3 items with files, ≥3 distinct)
#   blocked     — blocker cascade chain (gate: blocked items must exist)
#   all         — all of the above (default)
#
# Output: Mermaid fenced blocks printed to stdout, separated by blank lines.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Abbreviate a title to max_words words, stripping Mermaid-unsafe characters.
def abbrev [title: string, max_words: int = 3]: nothing -> string {
    let t = $title
        | str replace --regex '\s*\(.*?\)' ''
        | str replace --regex '(?i)^(feat|fix|chore|docs|refactor|test)\s*[:/]\s*' ''
        | str replace --regex '#\d+' ''
        | str trim
    $t | split words | first $max_words | str join ' '
}

# Replace hyphens with underscores for Mermaid node IDs.
def node_id [id: string]: nothing -> string {
    $id | str replace --all '-' '_'
}

# Return the shortest unique suffix of a path among all_paths.
def file_display_name [path: string, all_paths: list<string>]: nothing -> string {
    let parts = ($path | path split)
    let n_parts = ($parts | length)
    mut result = $path
    for n in 1..($n_parts) {
        let candidate = ($parts | last $n | path join)
        let matches = ($all_paths | where { |p|
            ($p | path split | last $n | path join) == $candidate
        } | length)
        if $matches == 1 {
            $result = $candidate
            break
        }
    }
    $result
}

# ---------------------------------------------------------------------------
# Dependency inference
# ---------------------------------------------------------------------------

# Build {item_id: [dep_id, ...]} by scanning depends_on fields and extra notes.
def infer_dependencies [items: list<any>]: nothing -> record {
    # Build issue-number → item-id index from titles and descriptions
    let issue_to_id = (
        $items | reduce --fold {} { |item, acc|
            let text = ($item | get -i title | default '') + ' ' + ($item | get -i description | default '')
            let parsed = ($text | parse --regex '#(\d+)')
            if ($parsed | is-empty) {
                $acc
            } else {
                $acc | insert ($parsed | first | get capture0) $item.id
            }
        }
    )

    $items | reduce --fold {} { |item, acc|
        let item_id = $item.id
        let explicit = ($item | get -i depends_on | default [] | each { |d| $d | into string })

        let from_notes = (
            $item | get -i extra | default [] | each { |ex|
                let note = ($ex | get -i note | default '')
                let refs = ($note | parse --regex '(?i)depends on ([\w]+-\d+|#\d+)' | get -i capture1 | default [])
                $refs | each { |ref|
                    if ($ref | str starts-with '#') {
                        let num = ($ref | str substring 1..)
                        $issue_to_id | get -i $num | default null
                    } else {
                        $ref
                    }
                } | compact
            } | flatten
        )

        let all_deps = ($explicit ++ $from_notes | uniq)
        if ($all_deps | is-empty) {
            $acc
        } else {
            $acc | insert $item_id $all_deps
        }
    }
}

# ---------------------------------------------------------------------------
# Diagram: dependency
# ---------------------------------------------------------------------------

def diagram_dependency [items: list<any>, deps: record]: nothing -> string {
    let dep_keys = ($deps | columns)
    let dep_vals = ($deps | values | flatten)
    let in_graph = ($dep_keys ++ $dep_vals | uniq)

    if ($in_graph | is-empty) { return '' }

    let id_to_item = ($items | reduce --fold {} { |item, acc| $acc | insert $item.id $item })

    let nodes = ($items | where { |item| $item.id in $in_graph } | each { |item|
        let label = (abbrev ($item | get -i title | default $item.id))
        let status = ($item | get -i status | default 'open')
        let nid = (node_id $item.id)
        match $status {
            'blocked' => $"  ($nid)[\"($label)\"]:::blocked",
            'done'    => $"  ($nid)\(\"($label)\"\):::done",
            _         => $"  ($nid)[\"($label)\"]",
        }
    })

    let id_set = ($id_to_item | columns)
    let edges = ($dep_keys | each { |iid|
        $deps | get $iid | each { |dep|
            if $dep in $id_set {
                $"  (node_id $dep) --> (node_id $iid)"
            }
        }
    } | flatten | compact)

    [
        '```mermaid'
        'flowchart TD'
    ] ++ $nodes ++ [
        ''
        '  classDef blocked fill:#e67e22,color:#fff'
        '  classDef done fill:#27ae60,color:#fff'
        ''
    ] ++ $edges ++ [ '```' ] | str join "\n"
}

# ---------------------------------------------------------------------------
# Diagram: burn (pie)
# ---------------------------------------------------------------------------

def diagram_burn [items: list<any>]: nothing -> string {
    if ($items | length) < 3 { return '' }

    let counts = ($items | group-by { |item| $item | get -i status | default 'open' })

    let slices = (['done', 'open', 'blocked', 'parked'] | each { |s|
        let n = ($counts | get -i $s | default [] | length)
        if $n > 0 { $"  \"($s)\" : ($n)" }
    } | compact)

    if ($slices | is-empty) { return '' }

    [ '```mermaid' 'pie title Work Distribution' ] ++ $slices ++ [ '```' ] | str join "\n"
}

# ---------------------------------------------------------------------------
# Diagram: velocity (xychart-beta bar)
# ---------------------------------------------------------------------------

def diagram_velocity [log_entries: list<any>, items: list<any>]: nothing -> string {
    if ($log_entries | length) < 2 { return '' }

    let completed_by_date = (
        $items
        | where { |item| ($item | get -i completed | default null) != null }
        | reduce --fold {} { |item, acc|
            let d = ($item.completed | into string)
            let n = ($acc | get -i $d | default 0)
            $acc | upsert $d ($n + 1)
        }
    )

    if ($completed_by_date | is-empty) { return '' }

    let log_dates = (
        $log_entries
        | each { |e| $e | get -i date | default null }
        | compact
        | each { |d| $d | into string }
        | uniq
        | sort
    )

    let counts = ($log_dates | each { |d| $completed_by_date | get -i $d | default 0 })
    let max_count = ($counts | math max)

    if $max_count == 0 { return '' }

    let labels = ($log_dates | each { |d| $"\"($d)\"" } | str join ', ')

    [
        '```mermaid'
        'xychart-beta'
        '  title "Items Completed"'
        $"  x-axis [($labels)]"
        $"  y-axis \"Items\" 0 --> ($max_count)"
        $"  bar ($counts)"
        '```'
    ] | str join "\n"
}

# ---------------------------------------------------------------------------
# Diagram: hotspots (xychart-beta bar)
# ---------------------------------------------------------------------------

def diagram_file_hotspots [items: list<any>, top_n: int = 8]: nothing -> string {
    let items_with_files = ($items | where { |item|
        let f = ($item | get -i files | default null)
        $f != null and ($f | length) > 0
    })

    if ($items_with_files | length) < 3 { return '' }

    let all_paths = ($items_with_files | each { |item| $item.files } | flatten)
    if ($all_paths | uniq | length) < 3 { return '' }

    let file_item_count = (
        $items_with_files | reduce --fold {} { |item, acc|
            let files = ($item.files | uniq)
            $files | reduce --fold $acc { |f, a|
                let n = ($a | get -i $f | default 0)
                $a | upsert $f ($n + 1)
            }
        }
    )

    let top = (
        $file_item_count
        | transpose key val
        | sort-by val --reverse
        | first $top_n
    )

    let all_path_keys = ($file_item_count | columns)
    let labels = ($top | each { |row| $"\"(file_display_name $row.key $all_path_keys)\"" } | str join ', ')
    let counts = ($top | each { |row| $row.val })
    let max_count = ($counts | math max)

    [
        '```mermaid'
        'xychart-beta'
        '  title "File Hotspots"'
        $"  x-axis [($labels)]"
        $"  y-axis \"Items\" 0 --> ($max_count)"
        $"  bar ($counts)"
        '```'
    ] | str join "\n"
}

# ---------------------------------------------------------------------------
# Diagram: blocked chain
# ---------------------------------------------------------------------------

def diagram_blocked_chain [items: list<any>, deps: record]: nothing -> string {
    let blocked_ids = (
        $items
        | where { |item| ($item | get -i status | default '') == 'blocked' }
        | each { |item| $item.id }
    )

    if ($blocked_ids | is-empty) { return '' }

    let dep_of_blocked = ($blocked_ids | each { |iid| $deps | get -i $iid | default [] } | flatten)
    let chain_ids = ($blocked_ids ++ $dep_of_blocked | uniq)

    let dep_cols = ($deps | columns)
    let root_blockers = (
        $items | where { |item|
            ($item | get -i status | default '') == 'blocked'
            and ($item | get -i extra | default [] | any { |ex|
                ($ex | get -i type | default '') == 'blocker'
            })
            and not ($item.id in $dep_cols)
        } | each { |item| $item.id }
    )

    let all_chain = ($chain_ids ++ $root_blockers | uniq | sort)
    if ($all_chain | is-empty) { return '' }

    let id_to_item = ($items | reduce --fold {} { |item, acc| $acc | insert $item.id $item })

    let nodes = ($all_chain | each { |iid|
        let item = ($id_to_item | get -i $iid | default {})
        let label = (abbrev ($item | get -i title | default $iid))
        let status = ($item | get -i status | default 'open')
        let nid = (node_id $iid)
        if ($iid in $root_blockers) and ($status == 'blocked') {
            $"  ($nid)[\"($label)\"]:::root_blocker"
        } else if $status == 'blocked' {
            $"  ($nid)[\"($label)\"]:::blocked"
        } else {
            $"  ($nid)[\"($label)\"]:::pending"
        }
    })

    let dep_edges = ($all_chain | each { |iid|
        $deps | get -i $iid | default [] | each { |dep|
            if $dep in $all_chain {
                $"  (node_id $dep) --> (node_id $iid)"
            }
        }
    } | flatten | compact)

    let dotted_edges = (
        $blocked_ids | where { |iid| not ($iid in $root_blockers) } | each { |iid|
            let has_dep = ($deps | get -i $iid | default [] | any { |dep| $dep in $all_chain })
            if not $has_dep {
                $root_blockers | each { |rb| $"  (node_id $rb) -.-> (node_id $iid)" }
            }
        } | flatten | compact
    )

    [
        '```mermaid'
        'flowchart TD'
    ] ++ $nodes ++ [
        ''
    ] ++ $dep_edges ++ $dotted_edges ++ [
        ''
        '  classDef root_blocker fill:#c0392b,color:#fff'
        '  classDef blocked fill:#e67e22,color:#fff'
        '  classDef pending fill:#2980b9,color:#fff'
        '```'
    ] | str join "\n"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [
    --handoff: string,          # Path to HANDOFF.*.yaml (required)
    --diagram: string = 'all',  # Which diagram: dependency|burn|velocity|hotspots|blocked|all
] {
    if ($handoff | is-empty) {
        print --stderr 'error: --handoff is required'
        exit 1
    }

    let path = ($handoff | path expand)
    if not ($path | path exists) {
        print --stderr $"error: file not found: ($path)"
        exit 1
    }

    let data = (open --raw $path | from yaml)
    let items = ($data | get -i items | default [])

    if ($items | is-empty) {
        print --stderr 'error: no items found in HANDOFF file'
        exit 1
    }

    let log_entries = ($data | get -i log | default [])
    let deps = (infer_dependencies $items)

    let all_diagrams = ['dependency', 'burn', 'velocity', 'hotspots', 'blocked']
    let to_run = if $diagram == 'all' { $all_diagrams } else { [$diagram] }

    let outputs = ($to_run | each { |name|
        let out = match $name {
            'dependency' => (diagram_dependency $items $deps),
            'burn'       => (diagram_burn $items),
            'velocity'   => (diagram_velocity $log_entries $items),
            'hotspots'   => (diagram_file_hotspots $items),
            'blocked'    => (diagram_blocked_chain $items $deps),
            _            => '',
        }
        if ($out | str length) > 0 {
            $"### ($name | str capitalize)\n\n($out)"
        }
    } | compact)

    $outputs | str join "\n\n"
}
