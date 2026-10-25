import {test,expect} from '@playwright/test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const run=promisify(execFile);
test('Accounting selected volume, invoice and its linked UPD and registry',async({baseURL},info)=>{
 test.setTimeout(120000);
 const {stdout}=await run(process.execPath,['tests/accounting.browser.mjs'],{cwd:process.cwd(),timeout:110000,env:{...process.env,CRM_BROWSER_URL:baseURL,CRM_BROWSER_MODE:info.project.use.isMobile?'mobile':'desktop',CRM_BROWSER_ARTIFACTS:info.outputPath('accounting')}});
 expect(stdout).toContain('linked invoice/UPD/registry');
});
