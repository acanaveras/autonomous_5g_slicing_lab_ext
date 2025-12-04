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
  // Fix cross-origin HMR issues in cloud environments (Brev.dev, CodeSpaces, etc.)
  allowedDevOrigins: [
    '*.brevlab.com',
    '*.github.dev',
  ],
  // Fix webpack hot update 404 errors
  webpack: (config, { dev, isServer }) => {
    if (dev && !isServer) {
      config.devServer = {
        ...config.devServer,
        writeToDisk: true,
      };
    }
    return config;
  },
  async redirects() {
    return [];
  },
};

module.exports = nextConfig;
