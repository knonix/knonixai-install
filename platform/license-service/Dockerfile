FROM node:22-alpine
WORKDIR /app
COPY server.mjs ./server.mjs
RUN mkdir -p /data
ENV KNONIX_LICENSE_DATA_DIR=/data
ENV PORT=8787
EXPOSE 8787
CMD ["node", "server.mjs"]
