FROM segment/chamber:2 AS chamber

# Create image based on the official Node image from dockerhub
FROM node:lts-buster-slim AS final

# Fixes an issue with Fargate containers needing root certificates installed.
RUN apt-get update && apt-get install -y openssl ca-certificates

RUN npm install -g serve

COPY --from=chamber /chamber /bin/chamber

# Create app directory
WORKDIR /usr/src/app

# Copy dependency definitions
COPY package.json /usr/src/app
COPY package-lock.json /usr/src/app

# Install dependecies
#RUN npm set progress=false \
#    && npm config set depth 0 \
#    && npm i install
RUN npm ci

# Get all the code needed to run the app
COPY . /usr/src/app

RUN npm run-script build

# Expose the port the app runs in
EXPOSE 5000

# Serve the app
CMD chamber exec backend -- serve -s
