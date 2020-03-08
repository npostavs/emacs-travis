Pre-built Emacs binaries for Travis CI.

Usage
=====

Add the following to your `.travis.yml`:

``` yaml
language: generic

env:
  matrix:
    - EMACS_VERSION=23.4
    - EMACS_VERSION=24.5
    - EMACS_VERSION=25.3
    - EMACS_VERSION=master

jobs:
  allow_failures:
    - env: EMACS_VERSION=master

install:
  - curl -LO https://github.com/npostavs/emacs-travis/releases/download/bins/emacs-bin-${EMACS_VERSION}.tar.gz
  - tar -xaf emacs-bin-${EMACS_VERSION}.tar.gz -C /
  # Configure $PATH: Emacs installed to /tmp/emacs
  - export PATH=/tmp/emacs/bin:${PATH}
  # Install dependencies for older Emacs versions which lack them.
  # Introduced in Emacs 24.3.
  - if ! emacs -Q --batch --eval "(require 'cl-lib)" ; then
        curl -Lo cl-lib.el http://elpa.gnu.org/packages/cl-lib-0.6.1.el ;
    fi
  # Introduced in Emacs 24.1
  - if ! emacs -Q --batch --eval "(require 'ert)" ; then
        curl -LO https://raw.githubusercontent.com/ohler/ert/c619b56c5bc6a866e33787489545b87d79973205/lisp/emacs-lisp/ert.el &&
        curl -LO https://raw.githubusercontent.com/ohler/ert/c619b56c5bc6a866e33787489545b87d79973205/lisp/emacs-lisp/ert-x.el ;
    fi
  - emacs --version

script:
  - make
  - make check
```

This setup tests your Emacs Lisp project on Emacs 23.4, 24.5, 25.3,
and the latest Emacs `master` version (assuming you have a `Makefile`
with a `check` target which runs your tests).  It includes code for
installing `cl-lib` and `ert` for older Emacs versions, you can remove
those steps if your package/tests don't depend on them (or your
package requires newer Emacs versions which already include them).

All point releases starting from 23.4 are also available if you want
to test more versions in between.  Daily builds of from the git
repository branches `master` and `emacs-27` are available as versions
`master` and `27`, respectively.  The latest pretest or release
candidate from the `emacs-27` branch is available as version
`27-prerelease` (this is updated manually, so may lag by a few days).

License
-------

Copyright © 2015-2020 Noam Postavsky <npostavs@users.sourceforge.net>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
