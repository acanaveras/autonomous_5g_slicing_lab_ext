const { configureRuntimeEnv } = require('next-runtime-env/build/configure');

// Check if Fast Refresh should be disabled
const shouldDisableFastRefresh = process.env.FAST_REFRESH === 'false';

const nextConfig = {
  env: {
    ...configureRuntimeEnv(),
  },
  output: 'standalone',
  typescript: {
    // !! WARN !!
    // Dangerously allow production builds to successfully complete even if
    // your project has type errors.
    // !! WARN !!
    ignoreBuildErrors: true,
  },
  eslint: {
    // !! WARN !!
    // Dangerously allow production builds to successfully complete even if
    // your project has ESLint errors.
    // !! WARN !!
    ignoreDuringBuilds: true,
  },
  experimental: {
    serverActions: {
      bodySizeLimit: process.env.NAT_MAX_FILE_SIZE_STRING || '5mb',
    },
  },
  // Disable Fast Refresh if FAST_REFRESH=false
  ...(shouldDisableFastRefresh && {
    reactStrictMode: false,
  }),
  // Fix cross-origin HMR issues in cloud environments (Brev.dev, CodeSpaces, etc.)
  allowedDevOrigins: [
    '*.brevlab.com',
    '*.github.dev',
  ],
  // Fix webpack hot update 404 errors and disable HMR if needed
  webpack: (config, { dev, isServer }) => {
    if (dev && !isServer) {
      // Disable HMR if FAST_REFRESH is false
      if (shouldDisableFastRefresh) {
        config.watchOptions = {
          ignored: /.*/,
        };
      } else {
        config.devServer = {
          ...config.devServer,
          writeToDisk: true,
        };
      }
    }
    return config;
  },
  async redirects() {
    return [];
  },
};

module.exports = nextConfig;
