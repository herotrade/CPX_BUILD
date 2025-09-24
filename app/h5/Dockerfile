FROM nginx:1.25-alpine

RUN apk add --no-cache unzip

COPY 1.zip /tmp/1.zip

RUN rm -rf /usr/share/nginx/html/* \
    && unzip -q /tmp/1.zip -d /usr/share/nginx/html \
    && rm /tmp/1.zip

# retain default CMD from base image
