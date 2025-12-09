const { configureRuntimeEnv } = require('next-runtime-env/build/configure');

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
  // Allow all origins for cross-origin requests in development
  allowedDevOrigins: ['*'],
  async redirects() {
    return [];
  },
};

module.exports = nextConfig;
