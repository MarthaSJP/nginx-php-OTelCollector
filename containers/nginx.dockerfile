FROM nginx:1.23.1-alpine as builder

RUN apk update \
  && apk add --update \
      alpine-sdk build-base cmake linux-headers libressl-dev pcre-dev zlib-dev \
      curl-dev protobuf-dev c-ares-dev \
      re2-dev abseil-cpp

# 依存関係にある gRPC のビルド
ENV GRPC_VERSION v1.43.2
RUN git clone --shallow-submodules --depth 1 --recurse-submodules -b ${GRPC_VERSION} \
  https://github.com/grpc/grpc \
  && cd grpc \
  && mkdir -p cmake/build \
  && cd cmake/build \
  && cmake \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_BUILD_TYPE=Release \
    -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
    ../.. \
  && make -j2 \
    && make install

# 依存関係にある opentelemetry-cpp のビルド
ENV OPENTELEMETRY_VERSION v1.3.0
RUN git clone --shallow-submodules --depth 1 --recurse-submodules -b ${OPENTELEMETRY_VERSION} \
  https://github.com/open-telemetry/opentelemetry-cpp.git \
  && cd opentelemetry-cpp \
  && mkdir build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_PREFIX_PATH=/install \
    -DWITH_ZIPKIN=OFF \
    -DWITH_JAEGER=OFF \
    -DWITH_OTLP=ON \
    -DWITH_OTLP_GRPC=ON \
    -DWITH_OTLP_HTTP=OFF \
    -DBUILD_TESTING=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_ABSEIL=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    .. \
  && make -j2 \
  && make install

# otel_ngx_module.so のビルド
RUN git clone https://github.com/open-telemetry/opentelemetry-cpp-contrib.git \
  && cd opentelemetry-cpp-contrib/instrumentation/nginx \
  && mkdir build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release \
    -DNGINX_BIN=/usr/sbin/nginx \
    -DCMAKE_PREFIX_PATH=/install \
    -DCMAKE_INSTALL_PREFIX=/usr/lib/nginx/modules \
    -DCURL_LIBRARY=/usr/lib/libcurl.so.4 \
    .. \
  && make -j2 \
  && make install

FROM nginx:1.23.1-alpine

RUN apk update \
  && apk add --update \
      grpc protobuf c-ares

# ビルドしたモジュールを実行環境へコピー
COPY --from=builder /usr/lib/nginx/modules/otel_ngx_module.so /usr/lib/nginx/modules/
# otel_ngx_module.soの設定ファイル所定の場所へコピー
COPY ./otel-nginx.toml /conf/otel-nginx.toml

# NGINXの設定ファイルを所定の場所へコピー
COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./nginx/default.conf /etc/nginx/conf.d/default.conf