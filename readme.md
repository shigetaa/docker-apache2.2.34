# Dockerfile からイメージを作成
AlpineLinux をベースに Apache をソースからインストールしてイメージを作成する。

## コンテナ 内で作業をする
```bash
docker run -it -p 8080:80 --name AL01 alpine:latest /bin/ash
```
下記のようにデフォルトシェルが出力され、コマンドが入力できます。
```bash
/ #
```
ホストのコンソールに戻る場合は、**Ctrl** + **Q** + **P** キーを同時に押すと戻ります。

もう一度、コンテナに戻る場合は、
```bash
docker attach AL01
```

## apk パッケージ管理を最新に更新する
```bash
apk update
```

## タイムゾーンの設定
以下のコマンドで日本標準時に設定する
```bash
apk add --no-cache tzdata && cp /usr/share/zoneinfo/Japan /etc/localtime && apk del tzdata
```

## Service 管理 OpenRC をインストールする
OpenRC をインストールすると以下のコマンドが利用できサーバー起動時に実行するアプリケーションを管理できる。
`rc-status` `rc-service` `rc-update`
```bash
apk add --no-cache openrc && openrc && touch /run/openrc/softlevel
```

## Apache をインストールする
Alpine Linux のパッケージ管理コマンド　`apk` を利用して
Apache をインストールしてみる
```bash
apk add apache2
```
以上簡単だ。


## tar.gz から Apache をインストールする
ユーザー＆グループを作成する
```bash
set -x
addgroup -g 82 -S www-data
adduser -u 82 -D -S -G www-data www-data
```
環境変数を設定する
```bash
export HTTPD_PREFIX=/usr/local/apache2
export PATH=$HTTPD_PREFIX/bin:$PATH
export HTTPD_VERSION=2.2.34
```
インストールフォルダ＆パーミッションを設定する
```bash
mkdir -p "$HTTPD_PREFIX"/src
chown www-data:www-data "$HTTPD_PREFIX"
```
必要なパッケージをインストールする
※必要なパッケージをインストールする
```bash
apk add --no-cache --virtual .build-deps gcc make ncurses-dev apr-dev apr-util-dev dpkg-dev dpkg coreutils gnupg libc-dev libressl libressl-dev libxml2-dev lua-dev nghttp2-dev pcre-dev tar zlib-dev
```
```bash
apk add --no-cache imagemagick curl ca-certificates
```
Apache source をダウンロードする
```bash
cd $HTTPD_PREFIX
wget -O httpd-$HTTPD_VERSION.tar.gz https://archive.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.gz
```
```bash
tar zxvf httpd-$HTTPD_VERSION.tar.gz -C src --strip-components=1 && rm httpd-$HTTPD_VERSION.tar.gz && cd src
```
インストール設定をする
```bash
gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
```
```bash
./configure \
--build="$gnuArch" \
--with-expat=builtin \
--enable-so \
--enable-deflate=shared \
--enable-dav_fs=shared \
--enable-dav=shared \
--enable-rewrite
```
インストールする
```bash
make -j "$(nproc)" && make install
```
後始末
```bash
cd $HTTPD_PREFIX
rm -r src man manual
```
起動設定
```bash
/usr/local/apache2/bin/apachectl start
```

## Dockerfile から Apache のコンテナイメージを作成
以下の `Dockerfile`ファイルを作成する。
```dockerfile
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
    tzdata \
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
  && cp /usr/share/zoneinfo/Japan /etc/localtime \
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
```

以下のコマンドで Dockerfile ファイルからコンテナイメージを作成する。
```bash
docker build -t イメージ名 Dockerfileディレクトリ
```
例 Apache のイメージを作成してみる
`-t` は イメージ名
最後の文字列は `Dockerfile` のディレクトリを指定します。 `.` はカレントディレクトリを表します。
```bash
docker build -t apache2.2.34 .
```

下記のコマンドでコンテナを動作させる
```bash
docker run -d -p 8080:80 --name コンテナ名 イメージ名
```
例 DocmentRoot をマウントしてコンテナを起動してみる。
`-d` は コンテナをバックグラウンドで実行させる
`-p` は ホストのポート番号:コンテナのポート番号
`-v` は ボリュームをマウントするオプションです。
`$Pwd` は Windowsのカレントディレクトリを返す変数
`--name` は コンテナ名を指定する
最後の文字列はイメージ名になります。
```bash
docker run -d -p 8080:80 -v $Pwd/public:/usr/local/apache2/htdocs --name container-apache apache2.2.34
```
実行中のコンテナでシェルを実行する
```bash
docker container exec -it container-apache /bin/ash
```