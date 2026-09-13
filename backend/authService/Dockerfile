FROM node:18-alpine AS base

WORKDIR /app

# Install build dependencies required for native modules (bcrypt)
RUN apk add --no-cache python3 make g++

# Copy package files
COPY package*.json ./

# Clean install with better error handling
RUN npm ci --only=production --ignore-scripts || npm install --only=production --ignore-scripts

# Copy application code
COPY . .

ENV NODE_ENV=production
EXPOSE 3001

CMD ["npm", "run", "start"]
