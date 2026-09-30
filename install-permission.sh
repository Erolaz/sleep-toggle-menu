#!/bin/sh
set -eu
target_user=${1:-}
case "$target_user" in
    ""|*[!A-Za-z0-9._-]*) echo "Invalid user name" >&2; exit 2 ;;
esac
[ "$(/usr/bin/id -u)" -eq 0 ] || { echo "Administrator privileges required" >&2; exit 3; }
user_id=$(/usr/bin/id -u "$target_user")
[ "$user_id" -ge 501 ] || { echo "A regular macOS user is required" >&2; exit 4; }
# Check current policy before adding anything. Never edit or delete other apps' rules.
/usr/sbin/visudo -c -f /private/etc/sudoers
policy_dir=/private/etc/sudoers.d
[ ! -L "$policy_dir" ] || { echo "Unexpected policy directory symlink" >&2; exit 5; }
if [ ! -d "$policy_dir" ]; then
    /usr/bin/install -d -o root -g wheel -m 0755 "$policy_dir"
fi
rule_path="$policy_dir/sleep-toggle-menu-$user_id"
[ ! -L "$rule_path" ] || { echo "Unexpected policy file symlink" >&2; exit 6; }
# Temporary filename contains a dot so sudo's includedir ignores it until the atomic rename.
temp_rule=$(/usr/bin/mktemp "$policy_dir/sleep-toggle-menu.XXXXXX")
trap '/bin/rm -f "$temp_rule"' EXIT HUP INT TERM
# Numeric UID avoids sudoers metacharacters in user names.
/usr/bin/printf '#%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$user_id" > "$temp_rule"
/usr/sbin/chown root:wheel "$temp_rule"
/bin/chmod 0440 "$temp_rule"
/usr/sbin/visudo -c -f "$temp_rule"
/bin/mv -f "$temp_rule" "$rule_path"
/usr/sbin/visudo -c -f /private/etc/sudoers
