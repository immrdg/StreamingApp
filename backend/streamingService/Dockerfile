FROM node:18-alpine AS base

WORKDIR /app

# Install dependencies for native modules if needed
RUN apk add --no-cache python3 make g++

# Copy package files
COPY streamingService/package*.json ./

# Install production dependencies
RUN npm install --production

# Copy application code
COPY streamingService/ ./

ENV NODE_ENV=production
EXPOSE 3002

CMD ["node", "index.js"]
