FROM segment/chamber:2 AS chamber

FROM node:lts-buster-slim as final

RUN apt-get update && apt-get install -y openssl ca-certificates

COPY --from=chamber /chamber /bin/chamber

# Create app directory
WORKDIR /usr/src/app

COPY package.json /usr/src/app/package.json
COPY package-lock.json /usr/src/app/package-lock.json
RUN npm ci

COPY . /usr/src/app

EXPOSE 3000

CMD chamber exec backend -- npm start
