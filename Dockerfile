FROM openresty/openresty:latest

RUN apt-get update -y && \
  apt-get install -y openresty-opm && \
  opm install zmartzone/lua-resty-openidc

COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
