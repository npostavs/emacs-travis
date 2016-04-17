#!/source/me/in/bash

prefix=/tmp/emacs
srcdir=/tmp/emacs-${EMACS_REV}
EMACSCONFFLAGS=(--with-x-toolkit=no --without-x
                # makeinfo is not available on the Travis VMs.
                --without-makeinfo
                CFLAGS='-O2 -march=native' --prefix="${prefix}")

CURL() {
    curl --silent --show-error --location "$@"
}
POST_FILE() {
     CURL -H 'Content-Type: application/octet-stream' --request POST --upload-file "$@"
}

gh_auth=(-H "Authorization: token ${github_token}")
gh_path=https://api.github.com/repos/npostavs/emacs-travis

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
    version=$(echo $EMACS_REV | sed 's/^emacs-//')
    local file=/tmp/emacs-bin-${version}.tar.gz
    tar -caPf "$file" "${prefix}" &&
        echo "$file"
}

# upload <filename> [label]
# Link will be at https://github.com/:user/:repo/releases/download/:tag/$(basename <filename>)
# [label] will be used the "pretty name" of the link (set to $(basename <filename>) if not given).
upload() {
    local filename=$1
    local name=$(basename "$filename")
    local label=${2:-$name}
    { read -r url; read -r old_id; read -r old_date;
    } < <(CURL "${gh_auth[@]}" $gh_path/releases |
                 JQ --raw-output "
map(select(.name == \"Binaries\")) | .[0] | (.upload_url / \"{?\" | .[0]), (.assets |
map(select(.name == \"$name\")) | .[0] | .id,.created_at)")
    echo "url: $url,  id: $old_id, date: $old_date" >&2

    if [ "$old_id" != null ] ; then
        if [ "$DISPOSE_OLD_BY" == rename ] ; then
            echo renaming old version... >&2
            CURL --request PATCH "${gh_auth[@]}" $gh_path/releases/assets/$old_id --data \
                 "{\"name\": \"$name-$old_date\", \"label\": \"$label from $old_date\"}"
        elif [ "$DISPOSE_OLD_BY" == delete ] ; then
            echo deleting old version... >&2
            CURL --request DELETE "${gh_auth[@]}" $gh_path/releases/assets/$old_id
        fi
    fi

    # upload the new version
    echo uploading... >&2
    POST_FILE "${filename}" -i "${gh_auth[@]}" "${url}?name=${name}&label=${label}"
}

# show definitions for log
printf ' (%s)' "${EMACSCONFFLAGS[@]}"
printf ' gh_path: (%s)' "${EMACSCONFFLAGS[@]}"
printf '\n'
declare -f download unpack autogen configure do_make get_jq pack upload
