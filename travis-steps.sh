#!/source/me/in/bash

prefix=/tmp/emacs
srcdir=/tmp/emacs-src
EMACSCONFFLAGS=(--with-x-toolkit=no --without-x --without-all
                --with-xml2 CFLAGS='-O2 -march=native' --prefix="${prefix}")

CURL() {
    curl --silent --show-error --location "$@"
}
POST_FILE() {
     CURL -H 'Content-Type: application/octet-stream' --request POST --upload-file "$@"
}

gh_auth=(-H "Authorization: token ${github_token}")
gh_path=https://api.github.com/repos/npostavs/emacs-travis

if [ "$EMACS_VERSION" = master ] ; then
    revname=master
else
    revname=emacs-${EMACS_VERSION}
fi

download() {
    url=https://github.com/emacs-mirror/emacs/archive
    CURL -o "/tmp/emacs-${EMACS_VERSION}.tar.gz" "$url/$revname.tar.gz"
}
unpack() {
    tar xzf "/tmp/emacs-${EMACS_VERSION}.tar.gz" -C /tmp
    mv "/tmp/emacs-${revname}" "${srcdir}"
}
autogen() {
    cd "${srcdir}" && ./autogen.sh
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
    local file=/tmp/emacs-bin-${EMACS_VERSION}.tar.gz
    tar -czf "$file" "${prefix}" &&
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
        # rename old version
        echo renaming old version... >&2
        CURL --request PATCH "${gh_auth[@]}" $gh_path/releases/assets/$old_id --data \
             "{\"name\": \"$name-$old_date\", \"label\": \"$label from $old_date\"}"
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
