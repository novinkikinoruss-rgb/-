import {defineConfig} from '@playwright/test';
export default defineConfig({
 testDir:'./tests/e2e',fullyParallel:true,retries:0,timeout:30000,
 use:{baseURL:'http://127.0.0.1:3000',browserName:'chromium',trace:'retain-on-failure'},
 webServer:{command:'npm start -- -H 127.0.0.1 -p 3000',url:'http://127.0.0.1:3000/api/health',reuseExistingServer:!process.env.CI,timeout:60000}
});
