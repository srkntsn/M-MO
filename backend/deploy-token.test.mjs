import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeDeploymentToken} from './deploy-token.mjs';
const token='aB_9-'.repeat(8);
test('deployment credentials accept copied tokens and harmless wrappers',()=>{
  for(const value of [token,' \n'+token+'\r\n','Bearer '+token,'"Bearer '+token+'"',"Bearer '"+token+"'",'“'+token+'”']) {
    assert.equal(normalizeDeploymentToken(value),token);
  }
});
test('deployment credentials reject labels, commands and internal line breaks without echoing secrets',()=>{
  for(const value of ['', 'CI/CD token for mimo-ai-server','curl -H Authorization: Bearer '+token,token.slice(0,20)+'\n'+token.slice(20)]) {
    assert.throws(()=>normalizeDeploymentToken(value),error=>!error.message.includes(token));
  }
});
