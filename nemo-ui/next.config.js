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
  // Configure webpack dev middleware
  ...(shouldDisableFastRefresh && {
    webpackDevMiddleware: config => {
      // Disable file watching in Docker
      config.watchOptions = {
        ignored: /.*/,
        poll: false,
      };
      return config;
    },
  }),
  // Fix webpack hot update 404 errors and disable HMR if needed
  webpack: (config, { dev, isServer, webpack }) => {
    if (dev && !isServer) {
      // Disable HMR completely if FAST_REFRESH is false
      if (shouldDisableFastRefresh) {
        // Remove HotModuleReplacementPlugin
        config.plugins = config.plugins.filter(
          plugin => plugin.constructor.name !== 'HotModuleReplacementPlugin'
        );
        // Disable hot reloading in webpack config
        if (config.entry && typeof config.entry === 'function') {
          const originalEntry = config.entry;
          config.entry = async () => {
            const entries = await originalEntry();
            Object.keys(entries).forEach(key => {
              if (Array.isArray(entries[key])) {
                entries[key] = entries[key].filter(
                  entry => !entry.includes('webpack-hot-middleware') &&
                           !entry.includes('webpack/hot/') &&
                           !entry.includes('react-refresh')
                );
              }
            });
            return entries;
          };
        }
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
