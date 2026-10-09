// MSG91 SendOTP keeps the code outside this application's database.
export function createOtpService({authKey=process.env.MSG91_AUTH_KEY,templateId=process.env.MSG91_TEMPLATE_ID,fetchImpl=fetch}={}){
 const configured=Boolean(authKey&&templateId);
 async function call(url,options){
  let response,data;
  try{response=await fetchImpl(url,{...options,headers:{...options.headers,authkey:authKey,Accept:'application/json'},signal:AbortSignal.timeout(10000)});data=await response.json();}
  catch{throw Object.assign(new Error('OTP service is unavailable. Please try later.'),{status:503});}
  if(!response.ok||data?.type!=='success')throw Object.assign(new Error('OTP service could not complete the request. Please try later.'),{status:503});
  return data;
 }
 return {
  configured,
  async send(phone){
   if(!configured)throw Object.assign(new Error('SMS login is not configured yet. Please contact KVK.'),{status:503});
   const url=new URL('https://control.msg91.com/api/v5/otp');
   url.searchParams.set('template_id',templateId);url.searchParams.set('mobile',`91${phone}`);url.searchParams.set('otp_length','6');url.searchParams.set('otp_expiry','5');
   await call(url,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
  },
  async verify(phone,code){
   if(!configured)throw Object.assign(new Error('SMS login is not configured yet. Please contact KVK.'),{status:503});
   const url=new URL('https://control.msg91.com/api/v5/otp/verify');
   url.searchParams.set('mobile',`91${phone}`);url.searchParams.set('otp',code);
   let response,data;
   try{response=await fetchImpl(url,{headers:{authkey:authKey,Accept:'application/json'},signal:AbortSignal.timeout(10000)});data=await response.json();}
   catch{throw Object.assign(new Error('OTP service is unavailable. Please try later.'),{status:503});}
   if(!response.ok)throw Object.assign(new Error('OTP service is unavailable. Please try later.'),{status:503});
   return data?.type==='success'&&/verified success|number_verified_successfully/i.test(String(data.message));
  }
 };
}
