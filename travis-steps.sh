# source me!

EMACSCONFFLAGS=(--with-x-toolkit=no --without-x --without-all --with-xml2 CFLAGS='-O2 -march=native')

if [ $EMACS_VERSION = 24.5 ] ; then
download() {
    curl -o "/tmp/emacs-${EMACS_VERSION}.tar.gz" "https://ftp.gnu.org/gnu/emacs/emacs-${EMACS_VERSION}.tar.gz"
}
unpack() {
    tar xzf "/tmp/emacs-${EMACS_VERSION}.tar.gz" -C /tmp
    mv /tmp/emacs-${EMACS_VERSION} /tmp/emacs
}
autogen() { :; }
else
download() {
    git clone --depth=1 'http://git.sv.gnu.org/r/emacs.git' /tmp/emacs
}
unpack() { :; }
autogen() {
    cd /tmp/emacs && ./autogen.sh
}
fi

configure() {
    cd '/tmp/emacs' && ./configure --quiet --enable-silent-rules --prefix="${HOME}" "${EMACSCONFFLAGS[@]}"
}

do_make() {
    make -j2 -C '/tmp/emacs' V=0 "$@"
}

# show definitions for log
printf ' (%s)' "${EMACSCONFFLAGS[@]}"
declare -f download unpack autogen configure do_make

