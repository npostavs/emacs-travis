#!/source/me/in/bash
# Copyright (C) 2015-2018 Noam Postavsky <npostavs@users.sourceforge.net>

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

EMACS_REV=$1
EMACS_VERSION=${2:-$(echo $EMACS_REV | sed 's/^emacs-//')}
if [ "$EMACS_VERSION" = master ] ; then
    # We can't compute correct version without downloading the tarball
    # first, and we need the value now.  To avoid having to update a
    # hardcoded value as Emacs progresses, just use a big number.
    EMACS_MAJOR_VERSION=999
else
    EMACS_MAJOR_VERSION=${EMACS_VERSION%%.*}
fi
github_token=$3
tmp=${4:-/tmp}


prefix=$tmp/emacs
srcdir=$tmp/emacs-${EMACS_REV}
mkdir -p $tmp/autoconf
EMACSCONFFLAGS=(--cache-file=$tmp/autoconf/config.cache
                --enable-silent-rules
                --with-x-toolkit=no --without-x
                # makeinfo is not available on the Travis VMs.
                --without-makeinfo
                CFLAGS='-O2' --prefix="${prefix}")

if [ "$EMACS_MAJOR_VERSION" -le 23 ] ; then
    # needed for Emacs 23.4 and lower
    EMACSCONFFLAGS+=(--with-crt-dir=/usr/lib/x86_64-linux-gnu)
fi
if [ "$EMACS_MAJOR_VERSION" -ge 25 ] ; then
    EMACSCONFFLAGS+=(--with-modules)
fi

EMACS_TARBALL=emacs-bin-${EMACS_VERSION}.tar.gz

CURL() {
    curl --dump-header $tmp/last-header.txt --silent --show-error --location "$@"
}
# Usage: [http-status-rx]
CHECK_HEADERS() {
    http_status_rx=${1:-2[0-9][0-9]}
    if grep -q "^HTTP[^ ]* $http_status_rx" $tmp/last-header.txt ; then
        # Show HTTP status and X-RateLimie-Remaining.
        sed -n '1p;/^X-RateLimit-Remaining/p' $tmp/last-header.txt
    else
        # Show all in case of error.
        cat $tmp/last-header.txt
        exit 1
    fi 1>&2
}
POST_FILE() {
    CURL -H 'Content-Type: application/octet-stream' --request POST \
         "${gh_auth[@]}" --upload-file "$@"
}

if [ -n "$github_token" ] ; then
    gh_auth=(-H "Authorization: token ${github_token}")
else
    gh_auth=()
fi
mirror_path=https://api.github.com/repos/emacs-mirror/emacs
binrel_path=https://api.github.com/repos/npostavs/emacs-travis

check_freshness() {
    if ! CURL "${gh_auth[@]}" $binrel_path/releases | tee $tmp/all-release.json |
            JQ 'map(select(.name == "Binaries")) | .[0]' > $tmp/releases.json ; then
        cat $tmp/all-release.json
        exit 1
    fi
    bin_data() {
        JQ --raw-output --arg name $EMACS_TARBALL \
           '.assets | map(select(.name == $name)) | .[0].label' $tmp/releases.json
        if [ $? -eq 4 ] ; then # jq --exit-status (4 == no result at all)
            echo "Failed to get binary data!"
            cat $tmp/last-header.txt
            cat $tmp/releases.json
            exit 1
        fi 1>&2
    }
    read -r name old_bin_date old_bin_hash < <(bin_data)
    commit_data() {
        CURL "${gh_auth[@]}" "$mirror_path/commits?sha=${EMACS_REV}&per_page=1" |
            tee $tmp/commit.json |
            JQ --raw-output '.[0] | (.commit.committer.date, .sha)'
        if [ "${PIPESTATUS[2]}" -eq 4 ] ; then
            echo "Failed to get commit data!"
            cat $tmp/last-header.txt
            cat $tmp/commit.json
            exit 1
        fi 1>&2
    }
    { read -r emacs_rev_date; read -r emacs_rev_hash; } < <(commit_data)
    if [ -z "$old_bin_date" ] ; then
        old_bin_date=never
    else
        ((date_diff=
          $(date --date=$emacs_rev_date +%s) -
          $(date --date=$old_bin_date   +%s) ))
        echo "date_diff = $date_diff"
    fi
    if [ "$old_bin_date" != never ] && ((date_diff < 24*60*60))
    then
        echo "${EMACS_REV} is sufficiently up to date." 1>&2
        echo "(it was last built ${old_bin_date}, source is from ${emacs_rev_date})" 1>&2
        exit 0
    else
        echo "${EMACS_REV} will be rebuilt." 1>&2
        echo "(it was last built ${old_bin_date}, source is from ${emacs_rev_date})" 1>&2
    fi
}
download() {
    url=https://github.com/emacs-mirror/emacs/archive
    CURL -o "$tmp/${EMACS_REV}.tar.gz" "$url/${EMACS_REV}.tar.gz"
}
unpack() {
    tar xzf "$tmp/${EMACS_REV}.tar.gz" -C $tmp
}
autogen() {
    # Emacs 23.4 (and lower) have ./configure checked in to the
    # repository already.
    cd "${srcdir}" && [ -x ./configure ] || ./autogen.sh
}

configure() {
    cd "${srcdir}" && ./configure "${EMACSCONFFLAGS[@]}"
}

do_make() {
    make -C "${srcdir}" V=1 "$@"
}

JQ() {
    "${JQ}" --exit-status "$@"
}
if JQ=$(which jq) ; then
    get_jq() { JQ --version; }
else
    JQ=$tmp/bin/jq
    get_jq() {
        mkdir -p "$(dirname "${JQ}")"
        CURL -o "${JQ}" https://stedolan.github.io/jq/download/linux64/jq &&
            chmod +x "${JQ}" &&
            JQ --version
    }
fi

pack() {
    tar -caPf "$tmp/$EMACS_TARBALL" "${prefix}"
    ls -lh "$tmp/$EMACS_TARBALL"
}

# Usage: <file> <upload-url> [label]
UPLOAD_FILE() {
    file=$1
    url=$2
    basename=$(basename $file)
    label=${3:-$basename}
    CURL -H 'Content-Type: application/octet-stream' --request POST \
         "${gh_auth[@]}" --upload-file "$file" \
         "$url" --get \
         --data-urlencode "name=$basename" \
         --data-urlencode "label=$label" > $tmp/upload.json
    CHECK_HEADERS
    JQ --raw-output .id $tmp/upload.json
}
# Usage: <file-id>
DELETE_FILE() {
    CURL --request DELETE "${gh_auth[@]}" \
         $binrel_path/releases/assets/$1
    CHECK_HEADERS
}
# Usage: <file-id> <new-name> [new-label]
RENAME_FILE() {
    data="{\"name\": \"$2\""
    [ -n "$3" ] && data+=", \"label\": \"$3\""
    data+="}"
    CURL --request PATCH "${gh_auth[@]}" \
         $binrel_path/releases/assets/$1 --data "$data"
    CHECK_HEADERS
}

upload() {
    read -r url < <(JQ --raw-output '.upload_url / "{?" | .[0]' $tmp/releases.json)

    # upload the new version
    echo "uploading... $EMACS_TARBALL $emacs_rev_date ${emacs_rev_hash:0:8}" >&2
    # NOTE: Github sees to have somme kind of bug/feature where the
    # "original extension" can't be changed by rename.  So put the
    # temp name part in front, not at the end.
    tmp_tarname=$emacs_rev_date.$EMACS_TARBALL
    mv "$tmp/$EMACS_TARBALL" "$tmp/$tmp_tarname"
    read -r new_bin_id < <(UPLOAD_FILE "$tmp/$tmp_tarname" "${url}" \
                           "$EMACS_TARBALL $emacs_rev_date ${emacs_rev_hash:0:8}")
    if [ -n "$new_bin_id" ] ; then
        echo "$new_bin_id"
    else
        # Failed to upload.
        JQ . $tmp/upload.json >&2
        return 1
    fi
}

replace_old() {
    if [ "$old_bin_date" != never ] ; then
        read -r old_bin_id < <(JQ --raw-output --arg name $EMACS_TARBALL '
            .assets | map(select(.name == $name)) | .[0].id' $tmp/releases.json)
        echo "renaming old version... (id=$old_bin_id)" >&2
        RENAME_FILE $old_bin_id "$name-$old_bin_date" "$name from $old_bin_date"
    fi

    echo "renaming new version to canonical name... (id=$new_bin_id)" >&2
    RENAME_FILE $new_bin_id "$EMACS_TARBALL"
}

delete_old() {
    if [ "$old_bin_date" != never ] ; then
        echo "deleting old version... (id=$old_bin_id)" >&2
        DELETE_FILE $old_bin_id
    fi
}

# show definitions for log
printf ' (%s)' "${EMACSCONFFLAGS[@]}"
printf '\n'
printf ' Binary releases path:  (%s)\n' "$binrel_path"
printf ' Emacs src mirror path: (%s)\n' "$mirror_path"
printf ' VERSION: %s, TARBALL: %s\n' "$EMACS_VERSION" "$EMACS_TARBALL"
printf ' JQ = %s\n' "$JQ"
printf '\n'
#declare -f download unpack autogen configure do_make get_jq pack upload
