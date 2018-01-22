#!/source/me/in/bash

EMACS_REV=$1
EMACS_VERSION=${2:-$(echo $EMACS_REV | sed 's/^emacs-//')}
github_token=$3


prefix=/tmp/emacs
srcdir=/tmp/emacs-${EMACS_REV}
mkdir -p /tmp/autoconf
EMACSCONFFLAGS=(#--cache-file=/tmp/autoconf/config.cache
                --quiet --enable-silent-rules
                --with-x-toolkit=no --without-x
                # makeinfo is not available on the Travis VMs.
                --without-makeinfo
                # needed for Emacs 23.4 and lower
                --with-crt-dir=/usr/lib/x86_64-linux-gnu
                CFLAGS='-O2' --prefix="${prefix}")

EMACS_TARBALL=emacs-bin-${EMACS_VERSION}.tar.gz

CURL() {
    curl --dump-header \
         >(tee /tmp/last-header.txt | sed -n '1p;/^X-RateLimit/p' 1>&2) \
         --silent --show-error --location "$@"
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
    echo null > /tmp/NULL.json
    CURL "${gh_auth[@]}" $binrel_path/releases | tee /tmp/all-release.json |
        JQ 'map(select(.name == "Binaries")) | .[0]' > /tmp/releases.json
    if diff -q /tmp/NULL.json /tmp/releases.json >/dev/null ; then
        cat /tmp/all-release.json
        exit 1
    fi
    bin_data() {
        JQ --raw-output --arg name $EMACS_TARBALL \
           '.assets | map(select(.name == $name)) | .[0].label' /tmp/releases.json
        if [ $? -eq 4 ] ; then
            echo "Failed to get binary data!"
            cat /tmp/last-header.txt
            cat /tmp/releases.json
            exit 1
        fi 1>&2
    }
    read -r name old_bin_date old_bin_hash < <(bin_data)
    commit_data() {
        CURL "${gh_auth[@]}" "$mirror_path/commits?sha=${EMACS_REV}&per_page=1" |
            tee /tmp/commit.json |
            JQ --raw-output '.[0] | (.commit.committer.date, .sha)'
        if [ "${PIPESTATUS[2]}" -eq 4 ] ; then
            echo "Failed to get commit data!"
            cat /tmp/last-header.txt
            cat /tmp/commit.json
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
    cd "${srcdir}" && ./configure "${EMACSCONFFLAGS[@]}"
}

do_make() {
    make -j2 -C "${srcdir}" V=0 "$@"
}

JQ() {
    "${JQ}" --exit-status "$@"
}
if JQ=$(which jq) ; then
    get_jq() { JQ --version; }
else
    JQ=/tmp/bin/jq
    get_jq() {
        mkdir -p "$(dirname "${JQ}")"
        CURL -o "${JQ}" https://stedolan.github.io/jq/download/linux64/jq &&
            chmod +x "${JQ}" &&
            JQ --version
    }
fi

pack() {
    tar -caPf "/tmp/$EMACS_TARBALL" "${prefix}"
    ls -lh "/tmp/$EMACS_TARBALL"
}

upload() {
    read -r url < <(JQ --raw-output '.upload_url / "{?" | .[0]' /tmp/releases.json)

    if [ "$old_bin_date" != never ] ; then
        read -r old_bin_id < <(JQ --raw-output --arg name $EMACS_TARBALL '
            .assets | map(select(.name == $name)) | .[0].id' /tmp/releases.json)
        if [ "$DISPOSE_OLD_BY" == rename ] ; then
            echo "renaming old version... (id=$old_bin_id)" >&2
            CURL --request PATCH "${gh_auth[@]}" $binrel_path/releases/assets/$old_bin_id --data \
                 "{\"name\": \"$name-$old_date\", \"label\": \"$label from $old_date\"}"
        elif [ "$DISPOSE_OLD_BY" == delete ] ; then
            echo "deleting old version... (id=$old_bin_id)" >&2
            CURL --request DELETE "${gh_auth[@]}" $binrel_path/releases/assets/$old_bin_id
        fi
    fi

    # upload the new version
    echo "uploading... $EMACS_TARBALL $emacs_rev_date ${emacs_rev_hash:0:8}" >&2
    POST_FILE "/tmp/$EMACS_TARBALL" "${url}" -i --get \
              --data-urlencode "name=$EMACS_TARBALL" \
              --data-urlencode \
              "label=$EMACS_TARBALL $emacs_rev_date ${emacs_rev_hash:0:8}"
}

# show definitions for log
printf ' (%s)' "${EMACSCONFFLAGS[@]}"
printf '\n Binary releases path:  (%s)\n' "$binrel_path"
printf ' Emacs src mirror path: (%s)\n' "$mirror_path"
printf ' VERSION: %s, TARBALL: %s\n' "$EMACS_VERSION" "$EMACS_TARBALL"
printf ' JQ = %s\n' "$JQ"
printf '\n'
#declare -f download unpack autogen configure do_make get_jq pack upload
