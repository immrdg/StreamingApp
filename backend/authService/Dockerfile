FROM node:18-alpine AS base

WORKDIR /app

# Install build dependencies required for native modules (bcrypt)
RUN apk add --no-cache python3 make g++

# Copy package files
COPY package*.json ./

# Install dependencies (production only, no scripts for bcrypt rebuild later)
RUN npm ci --only=production || npm install --only=production

# Copy application code
COPY . .

ENV NODE_ENV=production
EXPOSE 3001

CMD ["node", "index.js"]
