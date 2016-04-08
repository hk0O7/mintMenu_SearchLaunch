#!/bin/bash

getfilematches() {
	local grep_output="$*"
	cut -d ':' -f1 <<< "$grep_output" |
	  sort |
	  uniq -c |
	  sort -k1nr -k2d
}

query="$(
	sed -r 's/[^[:alnum:] ]*//g' <<< "$*"
)"

if [[ -z "$query" ]]; then
	printf 'Empty query.\n'
	exit 1
fi

IFS=' '
query_array=($query)

i=0; while [[ $i -lt ${#query_array[@]} ]]; do
	if [[ $i -eq 0 ]]; then
		search_results="$(
			grep -FirH --include="*.desktop" \
			  "${query_array[0]}" \
			  /usr/share/applications \
			  "$HOME"/.local/share/applications
		)"
	else
		search_results="$(
			IFS=$'\n'
			for file in $(
				getfilematches "$search_results" |
				  sed -r 's/^\s+[[:digit:]]+ //'
			); do
				grep -FiH "${query_array[i]}" "$file"
			done
		)"
	fi
	search_results="$(
		grep -E '\:(((Generic)?Name)|(Comment)|(Exec))=' <<< "$search_results"
	)"
	((i++))
done

if search_results_test="$(
	grep -Fi ":Name=$query" <<< "$search_results"
)"; then
	printf 'Full match in Name (first place).\n\n'
elif search_results_test="$(
	grep -F ':Name=' <<< "$search_results" |
	  grep -Fi "$query"
)"; then
	printf 'Full match in Name.\n\n'
elif search_results_test="$(
	grep -Ei "^[^\:]+$query[^\:]*\:" <<< "$search_results"
)"; then
	printf 'File name match.\n\n'
fi

if [[ -n "$search_results_test" ]]; then
	search_results="$search_results_test"
fi

search_results_recount="`getfilematches "$search_results"`"

if [[ $(wc -l <<< "$search_results_recount") -gt 7 ]]; then
	if [[ $(
		grep -E '^\s+1 ' <<< "$search_results_recount" |
		  wc -l
	) -gt 7 ]]; then
		printf 'Excessively ambiguous query.\n'
		exit 1
	fi
fi

target_desktop_file="$(
	head -n1 <<< "$search_results_recount" |
	  sed -r 's/^\s+[[:digit:]]+ //'
)"

if [[ -z "$target_desktop_file" ]]; then
	printf 'No match.\n'
	exit 1
fi

target_command=$(
	grep -E '^Exec=' "$target_desktop_file" |
	  head -n1 |
	  sed -r 's/(^Exec=)|( \%[[:alpha:]]\b)//g'
)

application_name="$(
	grep -E '^Name=' "$target_desktop_file" |
	  head -n1 |
	  cut -d '=' -f2
)"

if grep -qEi '^Terminal=true\b' "$target_desktop_file"; then
	if which 'mate-terminal' >/dev/null; then
		target_command="mate-terminal --title=\""$application_name"\" -e "$target_command""
	else
		target_command="x-terminal-emulator -e "$target_command""
	fi
fi

printf "\`%s'\n   |\n   \\-> %s\n        |\n        \\-> %s\t(%s)\n" \
  "$query" "$target_desktop_file" "$target_command" "$application_name"

notify-send -u low -t 1000 "$application_name" "Launching Application..."

eval setsid "$target_command" &>/dev/null & disown

exit 0

