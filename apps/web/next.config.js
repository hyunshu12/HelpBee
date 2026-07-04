const createNextIntlPlugin = require('next-intl/plugin');

const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ['@helpbee/ui', '@helpbee/types'],
  images: {
    domains: ['helpbee-images.s3.amazonaws.com', 'cdn.example.com'],
  },
};

module.exports = withNextIntl(nextConfig);
