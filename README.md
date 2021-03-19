# nginx-openid-demo

This is a demo of an `nginx` implementation with OpenID Connect (`keycloak`) with a Rest API (`elasticsearch`)

## Requirements

1. [Docker](https://www.docker.com/)
2. [Keycloak](https://www.keycloak.org/)
3. [Elasticsearch](https://www.elastic.co/elasticsearch/)

### Keycloak (OIDC)

[Download Keycloak](https://www.keycloak.org/downloads) and run it locally

```bash
$ cd keycloak-12.0.2
$ ./bin/standalone.sh
```

1. Create a `keycloak` realm, name it `test-nginx` (or anything you want)
   ![realm](./public/01_create_realm.png)

2. Create a client and name it `nginx`
   ![client](./public/02_create_client.png)

3. Use `confidentiial`
   ![confidential](./public/03_confidential.png)

4. Make sure to retrieve the `client_secret`
   ![client_secret](./public/04_client_secret.png)

5. Create a user in your realm, make sure to check `enbled` and set a <b>non temporary</b> password in the `credentials` tab
   ![create_user](./public/05_create_user.png)

6. Create a `.env` file and set your environment variables

```bash
REALM=test-nginx
CLIENT_ID=nginx
CLIENT_SECRET=client_secret_from_keycloak
```

## Elasticsearch

[Download Elasticsearch](https://www.elastic.co/downloads/elasticsearch) and run it locally:

```bash
$ cd elasticsearch-7.9.3
$ ./bin/elasticsearch
```

## NGINX

I'm using [OpenResty](https://openresty.org/en/) - a full-fledged web platform that integrates an enhanced open-sourced version of Nginx

- OpenID Connect integration is supported only in <b>[NGINX-PLUS](https://www.nginx.com/products/nginx/)</b>, but it requires a license

The [lua-resty-openidc](https://github.com/zmartzone/lua-resty-openidc) library is used to authenticate requests against the OpenID Connect server (`keycloak`)

Authentication is handled at the proxy level under a `lua` code block in `nginx.conf`

```lua
access_by_lua_block {
  local opts = {
    discovery = string.format("http://127.0.0.1/auth/realms/%s/.well-known/openid-configuration", os.getenv("REALM")),
    token_endpoint_auth_method = "client_secret_post",
    client_id = os.getenv("CLIENT_ID"),
    client_secret = os.getenv("CLIENT_SECRET"),
    scope = "openid email profile",
  }
  local json, err, access_token = require("resty.openidc").bearer_jwt_verify(opts)

  if err then
  ngx.status = 401
  ngx.say(string.format([[{"message": "%s"}]], err))
  ngx.exit(ngx.HTTP_UNAUTHORIZED)
  end
}
```
The JWT token is validated through the discovery endpoint: `.well-known/openid-configuration`
* Each incoming request will hit the `keycloak` token introspection endpoint to validate the token
* You can do offline token validation by adding a `public_key` in the `lua` code block: [LINK](https://github.com/zmartzone/lua-resty-openidc#sample-configuration-for-oauth-20-jwt-token-validation)


## Running the web-server

1. Build and run the docker image

```bash
$ docker-compose up --build
# Building web-server
# Step 1/3 : FROM openresty/openresty:latest
# .
# .
# .
# Step 3/3 : COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
#  ---> Using cache
#  ---> 0e304c9e93bb
# Successfully built 0e304c9e93bb
# Successfully tagged nginx-openid-demo_web-server:latest
# Recreating 3a87ad1d5f62_nginx-openid-demo_web-server_1 ... done
# Attaching to nginx-openid-demo_web-server_1
```

2. Retrieve an `access_token` from `keycloak`

```bash
$ export USERNAME=dustinlo
$ export PASSWORD=password
$ export REALM=test-nginx
$ export CLIENT_ID=nginx
$ export CLIENT_SECRET=client_secret_from_keycloak
$ export ACCESS_TOKEN=`curl -s \
   -d "client_id=$CLIENT_ID" -d "client_secret=$CLIENT_SECRET" \
   -d "username=$USERNAME" -d "password=$PASSWORD" \
   -d "grant_type=password" \
   "http://localhost/auth/realms/$REALM/protocol/openid-connect/token" | jq -r '.access_token'`

$ echo $ACCESS_TOKEN
# eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiw...Ji9KMRrshGR9psIAMk6upxb3g
```

3. Use attach the `access_token` in a `Authorization` header in your request to `elasticsearch`

```bash
$ curl -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost/es/
# {
#   "name" : "LMC-063631",
#   "cluster_name" : "elasticsearch",
#   "cluster_uuid" : "UeeuGwi3ThKFmruh9LO53A",
#   "version" : {
#     "number" : "7.9.3",
#     "build_flavor" : "default",
#     "build_type" : "tar",
#     "build_hash" : "c4138e51121ef06a6404866cddc601906fe5c868",
#     "build_date" : "2020-10-16T10:36:16.141335Z",
#     "build_snapshot" : false,
#     "lucene_version" : "8.6.2",
#     "minimum_wire_compatibility_version" : "6.8.0",
#     "minimum_index_compatibility_version" : "6.0.0-beta1"
#   },
#   "tagline" : "You Know, for Search"
# }
```

If you don't attach a header `nginx` will return a `401 Unauthorized` error

```bash
$ curl -s http://localhost/es/
# {
#   "message": "no Authorization header found"
# }
```

The server will also detect an expired or invalid token

```bash
$ curl -H 'Authorization: Bearer eyJhbGciOiJSUzI1NiIs...IVZPNrID8PIhg1o-g' http://localhost/es/
# {
#   "message": "jwt signature verification failed: 'exp' claim expired at Fri, 19 Mar 2021 19:58:08 GMT"
# }
```

This will not protect against making requests directly to `http://localhost:9200` but any requests through `nginx` will be protected
