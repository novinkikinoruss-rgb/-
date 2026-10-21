import type { NextConfig } from 'next';
const nextConfig: NextConfig = {
  async rewrites() {
    return [{source:'/supabase/:path*',destination:'https://yoqejkedmksmvbqagqru.supabase.co/:path*'}];
  },
};
export default nextConfig;
