FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache unzip

COPY 1.zip /app/1.zip

RUN unzip -q /app/1.zip -d /app \
    && rm /app/1.zip

EXPOSE 3000

CMD ["node", "server/index.mjs"]
