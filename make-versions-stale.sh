#!/source/me/in/bash

# Source after travis-steps.sh, see make_stale for Usage.

file_id_from_version () {
    tarball=emacs-bin-$1.tar.gz
    JQ --raw-output --arg name $tarball '
            .assets | map(select(.name == $name)) | .[0].id' $tmp/releases.json
}

label_from_id () {
    JQ --raw-output --argjson id $1 '
            .assets | map(select(.id == $id)) | .[0].label' $tmp/releases.json
}
name_from_id () {
    JQ --raw-output --argjson id $1 '
            .assets | map(select(.id == $id)) | .[0].name' $tmp/releases.json
}

# Usage: VERSION...
#
# Sets dates for given VERSIONs back by 10 years, so that they will be
# rebuilt on the next travis CI run.
make_stale () {
    for run in dry wet ; do
        if [ "$run" != dry ] ; then
            read -p 'Good to go? (yes/no) ' answer
            if [ "$answer" != yes ] ; then
                echo aborting
                return
            fi
        fi
        for v in "$@" ; do
            id=$(file_id_from_version $v)
            if [ -z "$id" ] || [ "$id" = null ] ; then
                echo "(v=$v) couldn't find id"
                continue
            fi
            name=$(name_from_id $id)
            label=$(label_from_id $id)
            read tarball date hash <<< "$label"

            if [ "$name" != "$tarball" ] ; then
                echo "(v=$v) $name != $tarball"
                continue
            fi
            echo "$name" \""$label"\"
            new_date=$(date --date="$date - 10 years" +%FT%TZ)
            new_label="$tarball $new_date $hash"
            if [ "$run" = dry ] ; then
                printf '  <<%s>>\n' RENAME_FILE $id $tarball "$new_label"
                printf '\n'
            else
                # RENAME_FILE calls CHECK_HEADERS which might exit.  So
                # run in a subshell.
                ( RENAME_FILE $id $tarball "$new_label" ) || return $?
            fi
        done
    done
}

make_stale "$@"
