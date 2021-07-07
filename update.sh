#!/bin/bash
#
# @package php/alpine/fpm
# @author  Yannoff <https://github.com/yannoff>
# @license MIT
#

generate_dockerfile(){
    local dockerfile version
    version=$1
    # Handle yamltools version
    # @see https://github.com/yannoff/yamltools/commit/0abfdf7c727db62062a24d2e3ec351d38abcd3f6
    if [ ${version} = "5.5" ]
    then
        yamltools_url=https://github.com/yannoff/yamltools/releases/download/1.3.3/yamltools
    else
        yamltools_url=https://github.com/yannoff/yamltools/releases/latest/download/yamltools
    fi

    case ${version} in
        5.5|5.6|7.0|7.1|7.2)
            image="${version}-fpm-alpine"
            ;;
        latest)
            image="fpm-alpine\${ALPINE_VERSION}"
            ;;
        *)
            image="${version}-fpm-alpine\${ALPINE_VERSION}"
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
ARG ALPINE_VERSION=3.13

FROM php:${image}

ARG PHP_EXTS="pdo_mysql pdo_pgsql intl opcache bcmath"
ARG APK_ADD

LABEL author="Yannoff <https://github.com/yannoff>" \\
      description="PHP-FPM with basic php extensions and composer" \\
      license="MIT"

ENV MUSL_LOCPATH /usr/local/share/i18n/locales/musl
# Fix ICONV library implementation
# @see https://github.com/docker-library/php/issues/240
ENV LD_PRELOAD /usr/local/lib/preloadable_libiconv.so

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/bin/

# Install basic packages & PHP extensions
RUN \\
    BUILD_DEPS="autoconf coreutils gcc libc-dev make patch"; \\
    apk add --update bash git vim \${APK_ADD} && \\
    \\
    # Keep a list of installed packages for after-cleanup restore
    export installed=\$(apk info | xargs); \\
    \\
    # Install temporary build dependencies
    apk add --no-cache --virtual build-deps \${BUILD_DEPS} && \\
    \\
    install-php-extensions \${PHP_EXTS} && \\
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
    rm -rf libiconv-1.14; \\
    \\
    # Use VIM for VI (instead of the poorly implemented BusyBox equivalent)
    rm /usr/bin/vi && ln -s /usr/bin/vim /usr/bin/vi && \\
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
    # Install yamltools standalone (ensure BC with any php version)
    curl -Lo /usr/local/bin/yamltools ${yamltools_url} && chmod +x /usr/local/bin/yamltools && \\
    # Install offenbach
    cd /tmp && git clone https://github.com/yannoff/offenbach.git && cd offenbach && \\
    # Use the latest release version instead of potentially unstable master
    offenbach_version=\$(git describe --tags --abbrev=0) && git checkout \${offenbach_version} && \\
    ./configure --bindir /usr/local/bin bin/offenbach && make && make install && \\
    cd /tmp && rm -rf offenbach && \\
    \\
    # Cleanup:
    # - remove build dependencies
    # - restore installed packages (avoid collision with build deps)
    # - remove C++ header files & PHP source tarball
    apk del --no-cache build-deps .locale-build-deps .iconv-build-deps; \\
    \\
    # Restore base installed packages, prevents accidental removal by build-deps cleanup
    # @see https://github.com/yannoff/docker-php-fpm/issues/28
    apk add --no-cache \${installed}; \\
    \\
    rm -rf  /usr/local/include/*; \\
    rm -rf /usr/src/*;
TEMPLATE

}

if [ $# -eq 0 ]
then
    # If no version specified, update all
    set -- 5.5 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1-rc
fi

for v in "$@"
do
    printf "Generating dockerfile for version %s..." ${v}
    mkdir -p $v 2>/dev/null
    generate_dockerfile $v
    printf "\033[01;32mOK\033[00m\n"
done

latest=$(ls [0-9]* -d | cat | tail -n 1)
printf "\nLinking latest image directory to version %s..." ${latest}
rm latest
ln -s ${latest} latest

printf "\nCopying latest version to root Dockerfile..."
cp latest/Dockerfile . 2>/dev/null
printf "\033[01;32mOK\033[00m\n"
