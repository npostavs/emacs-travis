#!/source/me/in/bash

prefix=/tmp/emacs
srcdir=/tmp/emacs-${EMACS_REV}
EMACSCONFFLAGS=(--with-x-toolkit=no --without-x
                # makeinfo is not available on the Travis VMs.
                --without-makeinfo
                # needed for Emacs 23.4 and lower
                --with-crt-dir=/usr/lib/x86_64-linux-gnu
                CFLAGS='-O2 -march=native' --prefix="${prefix}")
: ${EMACS_VERSION:=$(echo $EMACS_REV | sed 's/^emacs-//')}
EMACS_TARBALL=emacs-bin-${EMACS_VERSION}.tar.gz

CURL() {
    curl --silent --show-error --location "$@"
}
POST_FILE() {
    CURL -H 'Content-Type: application/octet-stream' --request POST \
         "${gh_auth[@]}" --upload-file "$@"
}

gh_auth=(-H "Authorization: token ${github_token}")
mirror_path=https://api.github.com/repos/emacs-mirror/emacs
binrel_path=https://api.github.com/repos/npostavs/emacs-travis

check_freshness() {
    CURL "${gh_auth[@]}" $binrel_path/releases |
        JQ 'map(select(.name == "Binaries")) | .[0]' > /tmp/releases.json
    read -r name old_bin_date old_bin_hash < <(JQ --raw-output --arg name $EMACS_TARBALL '
        .assets | map(select(.name == $name)) | .[0].label' /tmp/releases.json)
    { read -r emacs_rev_date; read -r emacs_rev_hash; } < <(
        CURL "$mirror_path/commits?sha=${EMACS_REV}&per_page=1" |
            jq --raw-output '.[0] | (.commit.committer.date, .sha)')
    if [ -z "$old_bin_date" ] ; then
        old_bin_date=never
    fi
    if [ "$old_bin_date" != never ] &&
           (($(date --date=$emacs_rev_date +%s) - $(date --date=$old_bin_date +%s)
             < 7*24*60*60))
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
    CURL -o "/tmp/${EMACS_REV}.tar.gz" "$url/${EMACS_REV}.tar.gz"
}
unpack() {
    tar xzf "/tmp/${EMACS_REV}.tar.gz" -C /tmp
}
autogen() {
    # Emacs 23.4 (and lower) have ./configure checked in to the
    # repository already.
    cd "${srcdir}" && [ -x ./configure ] || ./autogen.sh
}

configure() {
    cd "${srcdir}" && ./configure --quiet --enable-silent-rules --prefix="${HOME}" "${EMACSCONFFLAGS[@]}"
}

do_make() {
    make -j2 -C "${srcdir}" V=0 "$@"
}

JQ=/tmp/bin/jq
JQ() {
    "${JQ}" "$@"
}
get_jq() {
    mkdir -p "$(dirname "${JQ}")"
    CURL -o "${JQ}" https://stedolan.github.io/jq/download/linux64/jq &&
        chmod +x "${JQ}" &&
        JQ --version
}

pack() {
    tar -caPf "/tmp/$EMACS_TARBALL" "${prefix}"
}

upload() {
    read -r url < <(JQ --raw-output '.upload_url / "{?" | .[0]' /tmp/releases.json)

    if [ "$old_bin_date" != never ] ; then
        read -r old_bin_id < <(JQ --raw-output --arg name $EMACS_TARBALL '
            .[0].assets | map(select(.name == $name)) | .[0].id' /tmp/releases.json)
        if [ "$DISPOSE_OLD_BY" == rename ] ; then
            echo renaming old version... >&2
            CURL --request PATCH "${gh_auth[@]}" $binrel_path/releases/assets/$old_bin_id --data \
                 "{\"name\": \"$name-$old_date\", \"label\": \"$label from $old_date\"}"
        elif [ "$DISPOSE_OLD_BY" == delete ] ; then
            echo deleting old version... >&2
            CURL --request DELETE "${gh_auth[@]}" $binrel_path/releases/assets/$old_bin_id
        fi
    fi

    # upload the new version
    echo uploading... >&2
    POST_FILE "/tmp/$EMACS_TARBALL" "${url}" -i --get \
              --data-urlencode "name=$EMACS_TARBALL" \
              --data-urlencode "label=$EMACS_TARBALL $emacs_rev_date $emacs_rev_hash"
}

# show definitions for log
printf ' (%s)' "${EMACSCONFFLAGS[@]}"
printf ' Binary releases path:  (%s)' "$binrel_path"
printf ' Emacs src mirror path: (%s)' "$mirror_path"
printf ' VERSION: %s, TARBALL: %s' "$EMACS_VERSION" "$EMACS_TARBALL"
printf '\n'
declare -f download unpack autogen configure do_make get_jq pack upload
