import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createOtpService} from '../server/otp.mjs';

test('MSG91 OTP adapter sends and verifies a six-digit code server-side',async()=>{
 const requests=[];
 const service=createOtpService({authKey:'test-key',templateId:'test-template',fetchImpl:async(url,options)=>{
  requests.push({url:new URL(url),options});
  return {ok:true,json:async()=>requests.length===1?{type:'success',message:'sent'}:{type:'success',message:'OTP verified success'}};
 }});
 await service.send('9666666666');
 assert.equal(await service.verify('9666666666','123456'),true);
 assert.equal(requests[0].url.searchParams.get('mobile'),'919666666666');
 assert.equal(requests[0].url.searchParams.get('otp_length'),'6');
 assert.equal(requests[0].options.headers.authkey,'test-key');
 assert.equal(requests[1].url.searchParams.get('otp'),'123456');
});

test('unconfigured SMS provider never reports an OTP as sent',async()=>{
 const service=createOtpService({authKey:'',templateId:''});
 await assert.rejects(service.send('9666666666'),{status:503});
 await assert.rejects(service.verify('9666666666','123456'),{status:503});
});
