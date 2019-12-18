#!/bin/bash
#
# @package php/alpine/fpm
# @author  Yannoff <https://github.com/yannoff>
# @license MIT
#

generate_dockerfile(){
    local dockerfile version
    version=$1
    case ${version} in
        latest)
            image="fpm-alpine"
            ;;
        [0-9]*)
            image="${1}-fpm-alpine"
            ;;
    esac
    dockerfile=./${version}/Dockerfile
    cat > ${dockerfile} <<TEMPLATE
#
# This file is auto-generated by update.sh
#
# @package php/alpine/fpm
# @author  Yannoff <https://github.com/yannoff>
# @license MIT
#

FROM php:${image}

LABEL author="Yannoff <https://github.com/yannoff>" \\
      description="PHP-FPM with basic php extensions and composer" \\
      license="MIT"

ENV MUSL_LOCPATH /usr/local/share/i18n/locales/musl
# Fix ICONV library implementation
# @see https://github.com/docker-library/php/issues/240
ENV LD_PRELOAD /usr/local/lib/preloadable_libiconv.so

# Install basic packages & PHP extensions
RUN \\
    BUILD_DEPS="autoconf coreutils gcc libc-dev make"; \\
    apk add --update postgresql-dev icu-dev curl-dev libxml2-dev bash git && \\
    docker-php-ext-install pdo pdo_mysql pdo_pgsql intl curl json opcache xml bcmath; \\
    \\
    # Install temporary build dependencies
    apk add --no-cache --virtual build-deps \${BUILD_DEPS} && \\
    \\
    \\
    # Install support for locales
    # @see https://github.com/gliderlabs/docker-alpine/issues/144
    apk add --no-cache --virtual .locale-run-deps libintl && \\
    apk add --no-cache --virtual .locale-build-deps cmake make musl-dev gcc gettext-dev && \\
    cd /tmp && curl --output musl-locales-master.zip https://codeload.github.com/rilian-la-te/musl-locales/zip/master && \\
    unzip musl-locales-master.zip && cd musl-locales-master; \\
    cmake . && make && make install; \\
    cd .. && rm -rf /tmp/musl-locales-master*; \\
    \\
    # Fix ICONV library implementation
    # @see https://github.com/docker-library/php/issues/240
    # (could possibly be replaced by:
    #   apk add gnu-libiconv --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ --allow-untrusted; \\
    # @see https://github.com/wallabag/docker/pull/158/files
    # )
    apk add --no-cache --virtual .iconv-build-deps file libtool && \\
    curl -sSL http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz | tar -xz -C . && \\
    cd libiconv-1.14 && \\
    ./configure --prefix=/usr/local && \\
    curl -sSL https://raw.githubusercontent.com/mxe/mxe/7e231efd245996b886b501dad780761205ecf376/src/libiconv-1-fixes.patch | patch -p1 -u  && \\
    make && make install && \\
    libtool --finish /usr/local/lib; \\
    cd .. && \\
    rm -rfv libiconv-1.14; \\
    \\
    # Install composer
    #  - Download composer-setup.php & check for file integrity
    #  - Run composer installation script then remove it
    curl -sSL https://getcomposer.org/installer -o composer-setup.php; \\
    ACTUAL_SIG=\`sha384sum composer-setup.php | awk '{ printf "%s",\$1; }'\`; \\
    EXPECTED_SIG=\`curl -s https://composer.github.io/installer.sig | tr -d "\n"\`; \\
    [ "\$ACTUAL_SIG" = "\$EXPECTED_SIG" ] || echo "[composer] Error: signatures does not match!"; \\
    php composer-setup.php --filename=composer --install-dir=/usr/bin && \\
    rm composer-setup.php && \\
    \\
    # When the container is run as an unknown user (e.g 1000), COMPOSER_HOME defaults to /.composer
    mkdir /.composer && chmod 0777 /.composer; \\
    \\
    # Install offenbach
    cd /tmp && git clone https://github.com/yannoff/offenbach.git && cd offenbach; \\
    ./configure --bindir /usr/local/bin bin/offenbach && make && make install; \\
    cd /tmp && rm -rf offenbach; \\
    \\
    # Cleanup:
    # - remove build dependencies
    # - purge APK repository cache
    # - remove PHP source tarballs
    apk del build-deps .locale-build-deps .iconv-build-deps; \\
    rm -v /var/cache/apk/*; \\
    rm -rf /usr/src/*;
TEMPLATE

}

if [ $# -eq 0 ]
then
    printf "Usage: %s <version> [<version> [<version>]]\n" $0
    exit 1
fi

for v in "$@"
do
    printf "Generating dockerfile for version %s..." ${v}
    mkdir -p $v 2>/dev/null
    generate_dockerfile $v
    printf "\033[01;32mOK\033[00m\n"
done
printf "\nCopying latest version to root Dockerfile..."
cp latest/Dockerfile . 2>/dev/null
printf "\033[01;32mOK\033[00m\n"
