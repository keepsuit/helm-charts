# Reference image for charts/node: a Node server built in one stage, run in a slim one.
# Adapt the build command and the CMD to the framework's output.

FROM node:24-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:24-slim
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000
WORKDIR /app
COPY --from=build --chown=1000:1000 /app/.output ./.output
# Numeric UID: runAsNonRoot cannot verify a user name such as "node".
USER 1000
EXPOSE 3000
# node as PID 1 receives SIGTERM directly; npm start may not forward it.
CMD ["node", ".output/server/index.mjs"]
