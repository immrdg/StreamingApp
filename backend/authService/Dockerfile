FROM node:18-alpine AS base

WORKDIR /app

# Install build dependencies required for native modules (bcrypt)
RUN apk add --no-cache python3 make g++

# Copy package files
COPY authService/package*.json ./

# Install dependencies (production only)
RUN npm ci --only=production || npm install --only=production

# Copy application code
COPY authService/ ./

ENV NODE_ENV=production
EXPOSE 3001

CMD ["node", "index.js"]
