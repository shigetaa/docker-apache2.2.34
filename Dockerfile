FROM alpine:latest

RUN set -x \
  && adduser -u 82 -D -S -G www-data www-data

ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $HTTPD_PREFIX/bin:$PATH
ENV HTTPD_VERSION 2.2.34

RUN mkdir -p "$HTTPD_PREFIX" \
  && chown www-data:www-data "$HTTPD_PREFIX"

WORKDIR $HTTPD_PREFIX

RUN set -x \
  && runDeps=' \
    apr-dev \
    apr-util-dev \
    perl \
  ' \
  && apk add --no-cache --virtual .build-deps \
    $runDeps \
    ncurses-dev \
    ca-certificates \
    coreutils \
    dpkg-dev dpkg \
    gcc \
    gnupg \
    libc-dev \
    # mod_session_crypto
    libressl \
    libressl-dev \
    # mod_proxy_html mod_xml2enc
    libxml2-dev \
    # mod_lua
    lua-dev \
    make \
    # mod_http2
    nghttp2-dev \
    pcre-dev \
    tar \
    # mod_deflate
    zlib-dev \
  \
  && wget -O httpd-$HTTPD_VERSION.tar.gz https://archive.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.gz \
  && mkdir -p src \
  && tar zxvf httpd-$HTTPD_VERSION.tar.gz -C src --strip-components=1 \
  && rm httpd-$HTTPD_VERSION.tar.gz \
  && cd src \
  \
  && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
  && ./configure \
     --build="$gnuArch" \
     --with-expat=builtin \
     --enable-so \
     --enable-deflate=shared \
     --enable-dav_fs=shared \
     --enable-dav=shared \
     --enable-rewrite \
  && make -j "$(nproc)" \
  && make install \
  \
  && cd .. \
  && rm -r src man manual \
  \
  && sed -ri \
     -e 's!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g' \
     -e 's!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g' \
     "$HTTPD_PREFIX/conf/httpd.conf" \
  \
  && runDeps="$runDeps $( \
    scanelf --needed --nobanner --recursive /usr/local \
      | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
      | sort -u \
      | xargs -r apk info --installed \
      | sort -u \
  )" \
  && apk add --no-cache --virtual .httpd-rundeps $runDeps \
  && apk del .build-deps

COPY httpd-foreground /usr/local/bin/
RUN chmod 755 /usr/local/bin/httpd-foreground

EXPOSE 80
CMD ["httpd-foreground"]