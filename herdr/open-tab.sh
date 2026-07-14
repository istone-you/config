#!/bin/sh
# Usage: open-tab.sh <label> <command>
label="$1"
command="$2"

result=$(herdr tab create --label "$label" --no-focus)
pane_id=$(echo "$result" | jq -r '.result.root_pane.pane_id')
tab_id=$(echo "$result" | jq -r '.result.tab.tab_id')

herdr pane run "$pane_id" "$command; herdr tab close $tab_id"
herdr tab focus "$tab_id"
