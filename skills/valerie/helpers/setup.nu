#!/usr/bin/env nu
# valerie setup — detect backend, prompt for choices, write config
# Usage: nu setup.nu
# Writes: .claude-plugin/valerie.local.yaml

let plugin_dir = ($env.FILE_PWD | path join ".." ".." ".claude-plugin")
let config_file = ($plugin_dir | path join "valerie.local.yaml")

mkdir $plugin_dir

print ""
print "valerie setup"
print "============="
print ""

# --- Backend detection ---
let doob_found = (which doob | length) > 0

if $doob_found {
    let ver = (doob --version | str trim)
    print $"doob detected: ($ver)"
} else {
    print "doob not found on PATH."
}

# --- Backend choice ---
print ""
print "Choose a todo backend:"
print "  1) doob  — Rust + SurrealKV, agent-first, recommended"
print "  2) sqlite — lightweight fallback, sh/nu wrapper script"
print ""
let backend_choice = (input "Backend [1/2]: ")

let backend = if $backend_choice == "2" { "sqlite" } else { "doob" }

# --- If doob chosen but not found, offer install ---
if $backend == "doob" and not $doob_found {
    print ""
    print "doob is not installed. Install options:"
    print "  a) cargo install doob          (from crates.io — not yet published)"
    print "  b) cargo install --path <dir>  (from local clone)"
    print "  c) Skip — I will install manually"
    print ""
    let install_choice = (input "Choice [a/b/c]: ")

    match $install_choice {
        "b" => {
            let doob_path = (input "Path to doob repo: ")
            print $"Running: cargo install --path ($doob_path)"
            ^cargo install --path $doob_path
        }
        "c" => {
            print "Skipping install. Re-run setup after installing doob."
        }
        _ => {
            print "crates.io install not yet available. Use option b or c."
        }
    }
}

# --- Shell choice ---
print ""
print "Choose a shell for generated scripts:"
print "  1) sh   — POSIX, works everywhere"
print "  2) nu   — Nushell, richer output"
print ""
let shell_choice = (input "Shell [1/2]: ")

let shell_pref = if $shell_choice == "2" { "nu" } else { "sh" }

# --- Write config ---
let today = (date now | format date "%Y-%m-%d")
let config = $"# valerie local configuration — auto-generated, safe to edit
backend: ($backend)
shell: ($shell_pref)
configured: ($today)
"

$config | save --force $config_file

print ""
print $"Config written to: ($config_file)"
print ""
print $"  backend: ($backend)"
print $"  shell:   ($shell_pref)"
print ""
print "Setup complete. Valerie will use these settings going forward."
