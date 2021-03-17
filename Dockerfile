FROM nginx:latest

RUN apt-get update -y \
  & apt-get install -y wget vim

# RUN mkdir /tmp/nginx-lua \
#   & cd /tmp/nginx-lua

COPY nginx.conf ./etc/nginx/nginx.conf
