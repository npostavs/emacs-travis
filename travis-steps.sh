# source me!

EMACSCONFFLAGS=(--with-x-toolkit=no --without-x --without-all --with-xml2 CFLAGS='-O2 -march=native')

if [ $EMACS_VERSION = master ] ; then
    revname=master
else
    revname=emacs-$EMACS_VERSION
fi

download() {
    url=https://github.com/emacs-mirror/emacs/archive
    curl -Lo "/tmp/emacs-${EMACS_VERSION}.tar.gz" "$url/$revname.tar.gz"
}
unpack() {
    tar xzf "/tmp/emacs-${EMACS_VERSION}.tar.gz" -C /tmp
    mv /tmp/emacs-$revname /tmp/emacs
}
autogen() {
    cd /tmp/emacs && ./autogen.sh
}

configure() {
    cd '/tmp/emacs' && ./configure --quiet --enable-silent-rules --prefix="${HOME}" "${EMACSCONFFLAGS[@]}"
}

do_make() {
    make -j2 -C '/tmp/emacs' V=0 "$@"
}

# show definitions for log
printf ' (%s)' "${EMACSCONFFLAGS[@]}"
declare -f download unpack autogen configure do_make

