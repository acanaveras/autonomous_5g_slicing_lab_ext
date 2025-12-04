FROM node:18-alpine

# Install dependencies
RUN apk add --no-cache libc6-compat

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install all dependencies
RUN npm ci

# Copy proxy server and configuration
COPY proxy ./proxy
COPY next.config.js ./
COPY middleware.ts ./
COPY tsconfig.json ./
COPY next-i18next.config.js ./
COPY .eslintrc.js ./
COPY jest.config.js ./
COPY jest.setup.js ./
COPY postcss.config.js ./
COPY prettier.config.js ./
COPY tailwind.config.js ./
COPY vitest.config.ts ./

# Copy source code
COPY components ./components
COPY constants ./constants
COPY contexts ./contexts
COPY hooks ./hooks
COPY pages ./pages
COPY public ./public
COPY styles ./styles
COPY types ./types
COPY utils ./utils
COPY __mocks__ ./__mocks__
COPY __tests__ ./__tests__

# Expose only port 5001 (proxy server handles both API and Next.js)
EXPOSE 5001

# Environment variables
ENV NODE_ENV=development
ENV NEXT_TELEMETRY_DISABLED=1

# Run the dev server (proxy + Next.js)
CMD ["npm", "run", "dev"]
